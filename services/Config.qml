pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Single source of every tweakable value.
//
//   config/schema.json  describes each setting (section, label, description, type, range, default).
//                       Read-only; the shell takes its defaults from it.
//   config/config.jsonc  the user's values. May be partial: anything missing falls back to the
//                       schema default. JSON with comments and trailing commas allowed: the shipped file
//                       lists every setting commented out (= its default). Watched, so edits apply live.
//
// Components read values as  Config.<section>.<key>  (e.g. Config.island.color).
Singleton {
    id: root

    // ---- merged values (defaults from the schema, overridden by config.jsonc) ----
    property var data: build(userFile.text(), schemaFile.text())

    readonly property var font: data.font
    // the shell's own font, shipped in assets/fonts (font.bundled, Allo; SIL Open Font License): registered
    // for this process when the config is first read, before any text asks for it, so the island looks
    // the same on every computer, with or without the font installed
    FontLoader {
        source: root.font && root.font.bundled ? Qt.resolvedUrl("../assets/fonts/" + root.font.bundled) : ""
    }
    // colors, with the accent replaced by the system's (see _withAccent)
    readonly property var colors: _withAccent(data.colors)
    // colors.followSystemAccent: the desktop's accent name (systemAccent) looked up in colors.systemAccents
    // replaces colors.accent, when the system has one
    function _withAccent(c) {
        const own = c.followSystemAccent && c.systemAccents ? c.systemAccents[systemAccent] : "";
        return own ? Object.assign({}, c, { "accent": own }) : c;
    }
    // the desktop's accent name ("blue", "teal"... gsettings accent-color), set by Sys; "" = none known
    property string systemAccent: ""

    // ---- light / dark ----
    // The bar's icons stay white and the notch stays black whatever the mode; the dropdowns and the
    // notification cards follow it: colors.scheme ("system" = the desktop's gsettings color-scheme,
    // systemScheme, set by Sys; or "light" / "dark"). Their colors: colors.light / colors.dark.
    property string systemScheme: ""
    readonly property bool dark: colors.scheme === "dark" || (colors.scheme !== "light" && systemScheme === "prefer-dark")
    readonly property var theme: dark ? colors.dark : colors.light
    // the font's variable axes for a text of `pixelSize` and `weight`: its roundness (font.roundness), its
    // weight, and its optical size (Allo draws small text sturdier and big text finer; font.opticalSize).
    // The bundled font is one variable file, which Qt registers at its default weight only: every text
    // sets its axes (StyledText, the TextInputs).
    function axes(pixelSize, weight) {
        const a = {
            "ROND": font.roundness,
            "wght": weight
        };
        if (font.opticalSize)
            a.opsz = Math.max(font.opticalMin, Math.min(font.opticalMax, pixelSize));
        return a;
    }

    readonly property var bar: data.bar
    readonly property var island: data.island
    readonly property var motion: data.motion
    readonly property var activity: data.activity
    readonly property var panel: data.panel
    readonly property var tray: data.tray
    readonly property var battery: data.battery
    readonly property var wifi: data.wifi
    readonly property var bluetooth: data.bluetooth
    readonly property var time: data.time
    readonly property var media: data.media
    readonly property var wallpaper: data.wallpaper
    readonly property var carousel: data.carousel
    readonly property var shelf: data.shelf
    readonly property var quickSettings: data.quickSettings
    readonly property var search: data.search
    readonly property var system: data.system
    readonly property var slider: data.slider
    readonly property var volume: data.volume
    readonly property var brightness: data.brightness
    readonly property var microphone: data.microphone
    readonly property var message: data.message
    readonly property var lowBattery: data.lowBattery
    readonly property var charging: data.charging
    readonly property var wifiConnected: data.wifiConnected
    readonly property var headphones: data.headphones
    readonly property var nowPlaying: data.nowPlaying
    readonly property var notifications: data.notifications
    readonly property var screenshot: data.screenshot
    readonly property var goodbye: data.goodbye
    readonly property var sounds: data.sounds
    readonly property var screenCorners: data.screenCorners

    // ---- helpers for components ----

    // icon file name from the config -> url usable as an image source
    function icon(name) {
        return Qt.resolvedUrl("../assets/icons/" + name);
    }

    // icon file name -> its vector outline for widgets/Icon.qml: { path (SVG path data), x, y, w, h (viewBox),
    // evenOdd, parts (bounds of each subpath, see _parts) }. Each file is read once and cached. Only <path>
    // elements are read, without transforms (tools/check-config.py enforces it).
    property var _glyphs: ({})
    function glyph(name) {
        return _svg("icons", name);
    }
    // a handwriting from assets/handwriting (one or more stroked paths, e.g. goodbye's "bye bye"), read
    // the same way: { path, x, y, w, h (viewBox), ... }. Drawn as a stroke, not filled.
    function handwriting(name) {
        return _svg("handwriting", name);
    }
    function _svg(folder, name) {
        if (!name)
            return null;
        const key = folder + "/" + name;
        if (key in _glyphs)
            return _glyphs[key];
        // a full path ("/…/mouse-fill.svg") reads that file: icons another app provides, like the
        // Settings app's page icons in the launcher
        const file = svgFile.createObject(root, {
            "path": name.startsWith("/") ? "file://" + name : Qt.resolvedUrl("../assets/" + key)
        });
        const svg = file.text() || "";
        file.destroy();
        const head = (svg.match(/<svg\b[^>]*>/) || [""])[0];
        const box = ((head.match(/\sviewBox="([^"]*)"/) || [])[1] || "").trim().split(/[\s,]+/).map(Number);
        const paths = [];
        const re = /<path\b[^>]*?\sd="([^"]*)"/g;
        let m;
        // a path's first moveto is absolute even when written "m": keep it so once they're joined. The pairs
        // right after an "m" are relative line-tos, so they get an explicit "l" (as a plain "M" they'd turn
        // absolute: chevron-left.svg drew a slash)
        const num = "[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:e[-+]?\\d+)?";
        const lead = new RegExp("^m\\s*(" + num + ")[\\s,]*(" + num + ")(?=[\\s,]*[-+.\\d])", "i");
        while ((m = re.exec(svg)))
            paths.push(m[1].trim().replace(lead, (all, x, y) => all[0] === "m" ? "M" + x + " " + y + " l" : all).replace(/^m/, "M"));
        let g = null;
        if (box.length === 4 && box.every(n => !isNaN(n)) && paths.length)
            g = {
                "path": paths.join(" "),
                "x": box[0],
                "y": box[1],
                "w": box[2],
                "h": box[3],
                "evenOdd": /evenodd/.test(svg),
                "parts": _parts(paths.join(" "))
            };
        else
            console.warn("Config: " + key + " has no viewBox or no <path>");
        _glyphs[key] = g;
        return g;
    }
    // bounds { x, y, w, h } of each subpath (each moveto) of SVG path data, in viewBox units, from the
    // points the path goes through (control points ignored: close enough for the flat-sided shapes this
    // is used for, e.g. Battery finding the battery's body apart from its tip)
    function _parts(d) {
        const tokens = d.match(/[a-zA-Z]|-?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/gi) || [];
        // numbers taken by each command (its end point is always the last two, or the one for h / v)
        const arity = {
            "m": 2, "l": 2, "t": 2, "h": 1, "v": 1, "c": 6, "s": 4, "q": 4, "a": 7, "z": 0
        };
        const parts = [];
        let cmd = "", x = 0, y = 0, sx = 0, sy = 0, box = null, i = 0;
        const add = (px, py) => {
            if (!box) {
                box = { "x0": px, "y0": py, "x1": px, "y1": py };
                parts.push(box);
            }
            box.x0 = Math.min(box.x0, px); box.x1 = Math.max(box.x1, px);
            box.y0 = Math.min(box.y0, py); box.y1 = Math.max(box.y1, py);
        };
        while (i < tokens.length) {
            if (/[a-z]/i.test(tokens[i]))
                cmd = tokens[i++];
            const c = cmd.toLowerCase(), rel = cmd === c;
            if (!(c in arity))
                break;
            if (c === "z") {
                x = sx; y = sy;
                cmd = ""; // a number right after z is malformed: stop there instead of looping on it
                continue;
            }
            const n = tokens.slice(i, i + arity[c]).map(Number);
            i += arity[c];
            if (n.length < arity[c] || n.some(isNaN))
                break;
            if (c === "h")
                x = (rel ? x : 0) + n[0];
            else if (c === "v")
                y = (rel ? y : 0) + n[0];
            else {
                x = (rel ? x : 0) + n[n.length - 2];
                y = (rel ? y : 0) + n[n.length - 1];
            }
            if (c === "m") {
                box = null;
                sx = x; sy = y;
                cmd = rel ? "l" : "L"; // numbers after a moveto are linetos
            }
            add(x, y);
        }
        return parts.map(b => ({ "x": b.x0, "y": b.y0, "w": b.x1 - b.x0, "h": b.y1 - b.y0 }));
    }
    Component {
        id: svgFile
        FileView {
            blockLoading: true
        }
    }

    // Apple-style spring { response (s), dampingFraction (0-1, <1 bounces) } -> SpringAnimation values.
    // Qt's SpringAnimation steps every 16 ms with  v += spring*diff - damping*v ;  x += v*0.016
    // so  spring = w^2 * h  and  damping = 2*z*w * h,  with  w = 2pi / response,  h = 0.016.
    function spring(s) {
        const h = 0.016;
        const w = 2 * Math.PI / s.response;
        return {
            "spring": w * w * h,
            "damping": 2 * s.dampingFraction * w * h
        };
    }

    // ---- corners: one size per role (corners.*; the four corner styles were removed on 2026-11-23, the
    // user: "this makes the code clearer") ----
    // Roles: island (the pill-style notch), attached (the notch's bottom corners), flare, pill (100 = always
    // a pill), row (list highlights), menu (dropdowns, cards), tile (pictures), small (keycaps, the floor).
    // Things hugging an edge (badges) follow its corner instead (concentric: the corner minus the gap),
    // never below `small`.
    readonly property var corners: data.corners

    // the notch (island.style "notch": glued to the top edge, flares joining it) or a floating pill
    readonly property bool attached: island.style !== "pill"
    // height of a one-line pop-up in the island (volume, alerts): island.activityHeight
    readonly property real restHeight: island.activityHeight
    // that pop-up's corner (the bottom one in the notch), for what sits against its edge (badges)
    readonly property real restCorner: corner(attached ? "attached" : "island", restHeight)

    // the glyph color on a solid fill: white on a dark or saturated one (blue, red), the island's black on a
    // light one (yellow, green, white), by the fill's luminance (colors.lightFill)
    function onColor(fill) {
        const l = 0.2126 * fill.r + 0.7152 * fill.g + 0.0722 * fill.b;
        return l > colors.lightFill ? island.color : colors.text;
    }

    // corner for `role` on something `size` tall: the style's value, never more than half the size
    function corner(role, size) {
        return Math.max(0, Math.min(corners[role], size / 2));
    }
    // corner for something `size` tall sitting `inset` inside a shape whose corner is `outer`: concentric
    // with it, never below the style's `small` corner, never more than half the size
    function inner(outer, inset, size) {
        return Math.max(0, Math.min(Math.max(outer - inset, corners.small), size / 2));
    }

    // One continuous ("squircle") corner, Figma's corner smoothing: the arc is shortened and eased in by
    // two cubic curves, so the curvature ramps up instead of jumping like a plain arc. `budget` is the
    // longest the corner may run along each edge; smoothing gives way first when space is short (a pill
    // ends up with plain half circles).
    function cornerParams(r, s, budget) {
        r = Math.max(0, Math.min(r, budget));
        let p = (1 + s) * r;
        if (p > budget) {
            s = Math.max(0, budget / r - 1);
            p = budget;
        }
        const rad = Math.PI / 180;
        const arcMeasure = 90 * (1 - s);
        const arc = Math.sin(arcMeasure / 2 * rad) * r * Math.SQRT2;
        const alpha = (90 - arcMeasure) / 2;
        const p34 = r * Math.tan(alpha / 2 * rad);
        const beta = 45 * s;
        const c = p34 * Math.cos(beta * rad);
        const d = c * Math.tan(beta * rad);
        const b = (p - arc - c - d) / 3;
        return { r: r, p: p, a: 2 * b, b: b, c: c, d: d, arc: arc };
    }
    // SVG (relative commands) for a corner, drawn clockwise. k = quarter turns: 0 top-right, 1 bottom-right,
    // 2 bottom-left, 3 top-left.
    function cornerSvg(q, k) {
        if (q.r <= 0)
            return "";
        const pt = (x, y) => {
            for (let i = 0; i < k; i++)
                [x, y] = [-y, x];
            return x.toFixed(2) + " " + y.toFixed(2);
        };
        return " c " + pt(q.a, 0) + " " + pt(q.a + q.b, 0) + " " + pt(q.a + q.b + q.c, q.d)
            + " a " + q.r.toFixed(2) + " " + q.r.toFixed(2) + " 0 0 1 " + pt(q.arc, q.arc)
            + " c " + pt(q.d, q.c) + " " + pt(q.d, q.b + q.c) + " " + pt(q.d, q.a + q.b + q.c);
    }
    // SVG path of a w x h rectangle with smoothed corners of radius r (smoothing s, as island.cornerSmoothing):
    // the island's outline, the media covers
    function roundedRectPath(w, h, r, s) {
        if (w <= 0 || h <= 0)
            return "";
        const q = cornerParams(r, s, Math.min(w, h) / 2);
        const n = v => v.toFixed(2);
        return "M " + n(q.p) + " 0 H " + n(w - q.p) + cornerSvg(q, 0) + " V " + n(h - q.p) + cornerSvg(q, 1) + " H " + n(q.p) + cornerSvg(q, 2) + " V " + n(q.p) + cornerSvg(q, 3) + " Z";
    }
    // the screen corners (ScreenCorners): radius screenCorners.radius, smoothed by screenCorners.smoothing;
    // .p = how far each one runs along the screen's edges (its window's size)
    readonly property var screenCorner: cornerParams(screenCorners.radius, screenCorners.smoothing, screenCorners.radius * 2)

    // ---- internals ----

    // JSON with comments (// line, /* block */) and trailing commas -> plain JSON. String contents are
    // copied untouched; a comma is written only once the next real character isn't a closing bracket.
    function jsonc(text) {
        let out = "";
        let comma = false;
        let i = 0;
        const n = text.length;
        while (i < n) {
            const c = text[i];
            if (c === "/" && text[i + 1] === "/") {
                while (i < n && text[i] !== "\n")
                    i++;
            } else if (c === "/" && text[i + 1] === "*") {
                const end = text.indexOf("*/", i + 2);
                i = end < 0 ? n : end + 2;
            } else if (c === " " || c === "\t" || c === "\n" || c === "\r") {
                out += c;
                i++;
            } else if (c === ",") {
                if (comma)
                    out += ",";     // ",," stays invalid, as in JSON
                comma = true;
                i++;
            } else {
                if (comma && c !== "}" && c !== "]")
                    out += ",";
                comma = false;
                if (c === '"') {
                    let j = i + 1;
                    while (j < n && text[j] !== '"')
                        j += text[j] === "\\" ? 2 : 1;
                    out += text.slice(i, j + 1);
                    i = j + 1;
                } else {
                    out += c;
                    i++;
                }
            }
        }
        return out;
    }

    // nested object of schema defaults: "a.b.c": 1  ->  { a: { b: { c: 1 } } }
    function defaults(schema) {
        const out = {};
        for (const section of schema.sections || [])
            for (const group of section.groups || [])
                for (const s of group.settings || []) {
                    const parts = s.key.split(".");
                    let o = out;
                    for (let i = 0; i < parts.length - 1; i++)
                        o = o[parts[i]] = o[parts[i]] || {};
                    o[parts[parts.length - 1]] = s.default;
                }
        return out;
    }

    // user values win; objects merge key by key; arrays and scalars replace
    function merge(base, over) {
        if (over === undefined)
            return base;
        if (typeof base !== "object" || base === null || Array.isArray(base) || typeof over !== "object" || over === null || Array.isArray(over))
            return over;
        const out = Object.assign({}, base);
        for (const k in over)
            out[k] = merge(base[k], over[k]);
        return out;
    }

    // invalid config.jsonc: keep the previous values, or (at startup, when there are none) the schema
    // defaults, so a typo never takes the whole shell down. An unreadable schema.json (caught mid-write,
    // or empty for a moment) keeps the previous values too: building from no defaults left every
    // setting undefined and the whole island broken until the next good read (2026-11-19, 400+
    // warnings in a burst).
    function build(userText, schemaText) {
        let schema;
        try {
            schema = JSON.parse(schemaText);
        } catch (e) {
            if (root.data) {
                console.warn("Config: schema.json is not valid JSON, keeping the previous values:", e);
                return root.data;
            }
            schema = { "sections": [] };
        }
        const base = defaults(schema);
        let u;
        try {
            u = JSON.parse(jsonc(userText));
        } catch (e) {
            console.warn("Config: config.jsonc is not valid JSON, keeping the previous values:", e);
            return root.data || base;
        }
        return merge(base, u);
    }

    function reload() {
        const d = build(userFile.text(), schemaFile.text());
        if (d)
            root.data = d;
    }

    FileView {
        id: schemaFile
        path: Qt.resolvedUrl("../config/schema.json")
        blockLoading: true      // values must exist before the first frame
        watchChanges: true
        // reload() here is FileView's own (re-reads the file); onLoaded then rebuilds the values
        onFileChanged: reload()
        onLoaded: root.reload()
    }
    FileView {
        id: userFile
        path: Qt.resolvedUrl("../config/config.jsonc")
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.reload()
    }
}
