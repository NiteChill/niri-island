#!/usr/bin/env python3
"""Check that config/config.jsonc and config/schema.json agree.

Run from anywhere:  python3 tools/check-config.py
                    python3 tools/check-config.py --rewrite   (regenerate config.jsonc, see below)
Exit code 0 = all good, 1 = problems found (printed).

config.jsonc is JSON with comments and trailing commas. It lists every setting: the ones the user set are
plain lines, all the others are commented out ("// ") with their default value, so the file shows the
whole structure. --rewrite regenerates it that way: keeps the active lines (and their values), adds the
missing settings commented out, refreshes the commented values to the current defaults.

Checks:
  - every value in config.jsonc has a schema entry (no undocumented settings)
  - every setting is listed in config.jsonc (active or commented), commented ones with their default value
  - every schema entry has the required fields and a valid default for its type
  - every value in config.jsonc is valid for its type / range
  - every per-mode override object ("overrides": "<key>") only uses keys of that setting, with valid values
  - every QML Config.<path> read refers to a known setting, including reads through an alias
    (`readonly property var layout: Config.search` -> `layout.rowHeight` is checked as search.rowHeight)
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config" / "config.jsonc"
SCHEMA = ROOT / "config" / "schema.json"
HEADER = """/*
  Island settings. Every setting is listed with its default value, commented out with //.
  To change one, remove the // in front of its line (the { } lines of its section are always active).
  What each setting does: config/schema.json (or the settings app). Corners: pick a style with
  island.shape; each style's corner sizes are in island.shapes (services/Config.qml, corner()).
  Comments and trailing commas are allowed. Regenerate the commented lines:
  python3 tools/check-config.py --rewrite
*/
"""
REQUIRED = ("key", "label", "description", "type", "default")
# types whose value is an object/list stored under a single key
COMPOUND = {"spring", "object", "iconList", "actionList", "stringList", "integerList", "command"}
# helper functions / API on the Config singleton (not settings)
CONFIG_API = {"icon", "glyph", "spring", "data", "handwriting", "corner", "inner", "restCorner", "restHeight", "onColor", "systemAccent", "cornerParams", "cornerSvg", "screenCorner", "roundedRectPath"}
# aliases that aren't a plain `property var x: Config.path` (file name -> {alias: setting path})
EXTRA_ALIASES = {"IslandMode.qml": {"tr": "island.transition"}}

problems = []


def problem(msg):
    problems.append(msg)


def check_value(entry, value, where):
    t = entry["type"]
    key = entry["key"]
    if t in ("number", "integer"):
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            return problem(f"{where}: {key} should be a number, got {value!r}")
        if t == "integer" and float(value) != int(value):
            problem(f"{where}: {key} should be a whole number, got {value!r}")
        if "min" in entry and value < entry["min"]:
            problem(f"{where}: {key} = {value} is below min {entry['min']}")
        if "max" in entry and value > entry["max"]:
            problem(f"{where}: {key} = {value} is above max {entry['max']}")
    elif t == "color":
        if not (isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", value)):
            problem(f"{where}: {key} should be a color like \"#rrggbb\", got {value!r}")
    elif t in ("font", "string", "dateFormat", "icon"):
        if not isinstance(value, str):
            problem(f"{where}: {key} should be text, got {value!r}")
        elif "choices" in entry and value not in entry["choices"]:
            problem(f"{where}: {key} = {value!r} should be one of {', '.join(entry['choices'])}")
        elif t == "icon" and not (ROOT / "assets" / "icons" / value).exists():
            problem(f"{where}: {key}: icon file assets/icons/{value} does not exist")
    elif t == "handwriting":
        if not isinstance(value, str):
            problem(f"{where}: {key} should be a file name, got {value!r}")
        elif not (ROOT / "assets" / "handwriting" / value).exists():
            problem(f"{where}: {key}: file assets/handwriting/{value} does not exist")
    elif t == "stringList":
        if not isinstance(value, list) or not all(isinstance(v, str) and v for v in value):
            problem(f"{where}: {key} should be a list of (non-empty) text values")
    elif t == "integerList":
        if not isinstance(value, list) or not all(isinstance(v, int) and not isinstance(v, bool) for v in value):
            return problem(f"{where}: {key} should be a list of whole numbers")
        for v in value:
            if "min" in entry and v < entry["min"]:
                problem(f"{where}: {key} contains {v}, below min {entry['min']}")
            if "max" in entry and v > entry["max"]:
                problem(f"{where}: {key} contains {v}, above max {entry['max']}")
    elif t == "command":
        if not (isinstance(value, list) and value and all(isinstance(x, str) for x in value)):
            problem(f"{where}: {key} should be a command list like [\"program\", \"arg\"]")
    elif t == "iconList":
        if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
            problem(f"{where}: {key} should be a list of icon file names")
        elif "length" in entry and len(value) != entry["length"]:
            problem(f"{where}: {key} should have {entry['length']} icons")
    elif t == "actionList":
        if not isinstance(value, list):
            return problem(f"{where}: {key} should be a list of actions")
        for i, act in enumerate(value):
            for f in ("title", "icon", "command"):
                if f not in act:
                    problem(f"{where}: {key}[{i}] is missing {f!r}")
            if "command" in act and not (isinstance(act["command"], list) and act["command"] and all(isinstance(x, str) for x in act["command"])):
                problem(f"{where}: {key}[{i}].command should be a list like [\"program\", \"arg\"]")
            if "icon" in act and not (ROOT / "assets" / "icons" / act["icon"]).exists():
                problem(f"{where}: {key}[{i}]: icon file assets/icons/{act['icon']} does not exist")
    elif t == "spring":
        if not (isinstance(value, dict) and "response" in value and "dampingFraction" in value):
            problem(f"{where}: {key} should be {{\"response\": s, \"dampingFraction\": 0-1}}")
    elif t == "boolean":
        if not isinstance(value, bool):
            problem(f"{where}: {key} should be true or false, got {value!r}")
    elif t == "object":
        if not isinstance(value, dict):
            problem(f"{where}: {key} should be an object")
    else:
        problem(f"schema: {key} has unknown type {t!r}")


def jsonc(text):
    """JSON with // and /* */ comments and trailing commas -> plain JSON (same rules as Config.qml)."""
    out, comma, i, n = [], False, 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
        elif c in " \t\r\n":
            out.append(c)
            i += 1
        elif c == ",":
            if comma:
                out.append(",")
            comma = True
            i += 1
        else:
            if comma and c not in "}]":
                out.append(",")
            comma = False
            if c == '"':
                j = i + 1
                while j < n and text[j] != '"':
                    j += 2 if text[j] == "\\" else 1
                out.append(text[i:j + 1])
                i = j + 1
            else:
                out.append(c)
                i += 1
    return "".join(out)


def uncommented(text):
    """config.jsonc with every commented-out setting line made active (the header is a /* */ block)."""
    return re.sub(r"^(\s*)// ?", r"\1", text, flags=re.M)


def rewrite(full, active, entries, compound):
    """config.jsonc text: the structure (order) of `full`, active keys from `active` as plain lines, every
    other setting commented out with its default, missing settings added at the end of their section."""
    order = {}

    def walk(obj, prefix):
        for k, v in obj.items():
            path = f"{prefix}.{k}" if prefix else k
            order.setdefault(path, len(order))
            if path not in compound and path not in entries and isinstance(v, dict):
                walk(v, path)

    walk(full, "")
    tree = {}
    inside = {k for k in entries if any(k.startswith(c + ".") for c in compound)}
    for key in sorted(entries.keys() - inside, key=lambda k: order.get(k, len(order))):
        o = tree
        for part in key.split(".")[:-1]:
            o = o.setdefault(part, {})
        o[key.split(".")[-1]] = key
    # "$schema": tells editors (Zed, VS Code) that comments and trailing commas are fine here
    lines = [HEADER.rstrip("\n"), "{", '    "$schema": "./config.schema.json",']

    def emit(node, prefix, depth):
        pad = "    " * depth
        for k, v in node.items():
            path = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                lines.append(f"{pad}{json.dumps(k)}: {{")
                emit(v, path, depth + 1)
                lines.append(f"{pad}}},")
                continue
            on = lookup(active, path, missing=KeyError) is not KeyError
            value = lookup(active, path) if on else entries[path]["default"]
            body = json.dumps(value, indent=4, ensure_ascii=False).split("\n")
            body[0] = f"{json.dumps(k)}: {body[0]}"
            body[-1] += ","
            for b in body:
                lines.append(pad + ("" if on else "// ") + b)

    emit(tree, "", 1)
    lines.append("}")
    return "\n".join(lines) + "\n"


def leaves(obj, prefix, compound_keys):
    """Yield (dotted key, value) for config.jsonc, stopping at compound settings."""
    for k, v in obj.items():
        if not prefix and k.startswith("$"):
            continue     # "$schema": for editors, not a setting
        path = f"{prefix}.{k}" if prefix else k
        if path in compound_keys or not isinstance(v, dict):
            yield path, v
        else:
            yield from leaves(v, path, compound_keys)


def lookup(obj, key, missing=None):
    for k in key.split("."):
        if not isinstance(obj, dict) or k not in obj:
            return missing
        obj = obj[k]
    return obj


def main():
    schema = json.loads(SCHEMA.read_text())
    text = CONFIG.read_text()
    try:
        config = json.loads(jsonc(text))
        full = json.loads(jsonc(uncommented(text)))
    except json.JSONDecodeError as e:
        print(f"config.jsonc is not valid (JSON with comments): {e}")
        return 1

    entries = {}
    for section in schema["sections"]:
        for field in ("id", "title", "description", "groups"):
            if field not in section:
                problem(f"schema: section {section.get('id', '?')} is missing {field!r}")
        for group in section.get("groups", []):
            for e in group.get("settings", []):
                missing = [f for f in REQUIRED if f not in e]
                if missing:
                    problem(f"schema: {e.get('key', '?')} is missing {missing}")
                    continue
                if e["key"] in entries:
                    problem(f"schema: {e['key']} is listed twice")
                entries[e["key"]] = e
                check_value(e, e["default"], "schema default")

    compound = {k for k, e in entries.items() if e["type"] in COMPOUND}
    if "--rewrite" in sys.argv:
        # whole file at once (the live shell reloads on save and would catch a half-written file)
        tmp = CONFIG.with_suffix(".json.tmp")
        tmp.write_text(rewrite(full, config, entries, compound))
        tmp.replace(CONFIG)
        print("config.jsonc rewritten; checking it:")
        sys.argv.remove("--rewrite")
        problems.clear()
        return main()
    for key, value in leaves(config, "", compound):
        e = entries.get(key)
        if e is None:
            # values inside a compound setting (a spring's response, an action's command...) are checked
            # with that setting; anything else is undocumented
            if not any(key.startswith(c + ".") for c in compound):
                problem(f"config.jsonc: {key} has no schema entry (add it to config/schema.json)")
            continue
        check_value(e, value, "config.jsonc")

    # every setting is listed in config.jsonc: active, or commented out with its default
    for key, e in entries.items():
        if lookup(full, key, KeyError) is KeyError:
            problem(f"config.jsonc: {key} isn't listed (run python3 tools/check-config.py --rewrite to add it, commented out)")
        elif lookup(config, key, KeyError) is KeyError and lookup(full, key) != e["default"]:
            problem(f"config.jsonc: the commented-out {key} shows {lookup(full, key)!r}, but the default is {e['default']!r} (run --rewrite)")

    # override objects (e.g. battery.transition overrides island.transition): same keys, same rules
    for key, e in entries.items():
        target = e.get("overrides")
        if not target:
            continue
        value = lookup(config, key)
        for where, obj in (("schema default", e["default"]), ("config.jsonc", value)):
            if not isinstance(obj, dict):
                continue
            for sub, v in leaves(obj, "", compound):
                full = f"{target}.{sub}"
                if full in entries:
                    check_value(entries[full], v, f"{where} {key}")
                elif not any(full.startswith(c + ".") for c in compound):
                    problem(f"{where}: {key}.{sub} is not a setting of {target}")

    # QML reads must exist (prefix of or equal to a known key): Config.a.b, and reads through aliases
    known = set(entries)
    prefixes = {".".join(k.split(".")[:i]) for k in known for i in range(1, k.count(".") + 2)}

    def check_read(qml, path, shown):
        # anything after a full setting key is a property/method of its value (e.g. root.replace, .length)
        if path not in prefixes and not any(path.startswith(k + ".") for k in known):
            problem(f"{qml.relative_to(ROOT)}: reads {shown}, which is not in the schema ({path})")

    ident = r"((?:[a-zA-Z]\w*\.)*[a-zA-Z]\w*)"
    for qml in ROOT.rglob("*.qml"):
        if "old" in qml.relative_to(ROOT).parts:
            continue
        text = qml.read_text()
        for m in re.finditer(r"\bConfig\." + ident, text):
            if m.group(1).split(".")[0] not in CONFIG_API:
                check_read(qml, m.group(1), "Config." + m.group(1))
        aliases = dict(EXTRA_ALIASES.get(qml.name, {}))
        for m in re.finditer(r"property\s+var\s+(\w+)\s*:\s*Config\." + ident + r"\s*$", text, re.M):
            aliases[m.group(1)] = m.group(2)
        for alias, base in aliases.items():
            # `alias.x.y` but not `Config.alias...` / `something.Config...`; property calls like .toString skipped
            for m in re.finditer(r"(?<![\w])" + alias + r"\." + ident, text):
                check_read(qml, f"{base}.{m.group(1)}", f"{alias}.{m.group(1)}")

    # every top-level section used in the schema must be exposed by services/Config.qml
    # (`readonly property var foo: data.foo`), or `Config.foo.x` is undefined at runtime
    config_qml = (ROOT / "services" / "Config.qml").read_text()
    # (or passed through a helper first: `readonly property var colors: _withAccent(data.colors)`)
    exposed = set(re.findall(r"property\s+var\s+(\w+)\s*:\s*(?:\w+\()?data\.(\w+)", config_qml))
    exposed = {name for name, src in exposed if name == src}
    for top in sorted({k.split(".")[0] for k in known}):
        if top not in exposed:
            problem(f"services/Config.qml: section {top!r} isn't exposed (add `readonly property var {top}: data.{top}`)")

    # icons are drawn as vector paths by widgets/Icon.qml (Config.glyph), which reads only the viewBox and
    # the <path d="..."> data: anything else in the file (transforms, circles, strokes...) would be ignored
    for svg in sorted((ROOT / "assets" / "icons").glob("*.svg")):
        text = svg.read_text()
        where = f"assets/icons/{svg.name}"
        head = re.search(r"<svg\b[^>]*>", text)
        if not head or not re.search(r"\sviewBox=\"[^\"]+\"", head.group(0)):
            problem(f"{where}: the <svg> tag needs a viewBox")
        if not re.search(r"<path\b[^>]*?\sd=\"", text):
            problem(f"{where}: no <path d=\"...\"> to draw")
        if "transform" in text:
            problem(f"{where}: uses a transform, which Icon ignores (flatten it: move the offset into the viewBox, or apply it in Inkscape)")
        for tag in sorted(set(re.findall(r"<(circle|rect|ellipse|line|polyline|polygon|use|image|text)\b", text))):
            problem(f"{where}: <{tag}> isn't drawn by Icon (convert it to a <path>)")
        if re.search(r"\bstroke\s*[:=]\s*\"?(?!none|transparent)", text):
            problem(f"{where}: strokes aren't drawn by Icon (convert the stroke to a filled path)")

    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} problem(s).")
        return 1
    print(f"OK: {len(entries)} settings, config.jsonc and schema.json agree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
