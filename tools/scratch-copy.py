#!/usr/bin/env python3
"""Build a safe test copy of the shell (the default way to test, see CLAUDE.md "Testing a change").

  python3 tools/scratch-copy.py <dest> [--tester FILE] [--shelf DIR]
  qs -p <dest>        (run it; stop it with timeout -s TERM, it ignores SIGINT when backgrounded)

The copy can't touch the system or the user:
  - every command it could run is "true": search actions, opening / revealing files, the bar menus'
    commands, the shelf's trash and clipboard commands
  - sounds, wallpaper, volume, mute, mic, brightness and sound output changes are stubbed in its Sys
    (they log "TEST ..." instead: a test pressing Left on the volume row lowered the real volume)
  - its window never takes the keyboard (WlrKeyboardFocus.None: an open dropdown took it exclusively once,
    and the user's typing toggled their Wi-Fi) and reserves no space (exclusiveZone 0: the user's windows
    would move)
  - its shelf is its own folder (<dest>/shelf, or --shelf DIR), screenshots aren't put on it
The window's visual children sit in an `Item { id: scene }` so tests can grab it
(scene.grabToImage: the grab is transparent, composite it over a wallpaper), and a --tester file is
copied in as Tester.qml and instantiated next to the scene: it can reach `scene`, `bar`, `island`,
`dropdown`, `stack`, `tabs` and the singletons. A copy's history and pins live in its own
~/.local/state/quickshell/by-shell/<id> (the id is in its log): delete that folder afterwards.
"""
import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARTS = ["assets", "bin", "config", "island", "modes", "services", "surfaces", "tools", "widgets", "shell.qml", "ScreenCorners.qml"]
STUB = ["true"]


def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        sys.exit(__doc__)
    dest = os.path.abspath(args[0])
    tester = args[args.index("--tester") + 1] if "--tester" in args else None
    shelf = os.path.abspath(args[args.index("--shelf") + 1]) if "--shelf" in args else os.path.join(dest, "shelf")
    if dest == ROOT or ROOT.startswith(dest + os.sep):
        sys.exit("scratch-copy: refusing to write over the shell itself")

    for part in PARTS:
        src, dst = os.path.join(ROOT, part), os.path.join(dest, part)
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            os.makedirs(dest, exist_ok=True)
            shutil.copy2(src, dst)
    os.makedirs(shelf, exist_ok=True)

    # ---- settings: nothing that runs or touches the user's things ----
    path = os.path.join(dest, "config", "schema.json")
    schema = json.load(open(path))
    for section in schema["sections"]:
        for group in section["groups"]:
            for e in group["settings"]:
                k = e["key"]
                if k == "search.actions":
                    for a in e["default"]:
                        a["command"] = STUB
                elif k in ("search.files.openCommand", "search.files.revealCommand", "shelf.removeCommand", "shelf.copyCommand", "search.settings.openCommand", "search.web.browserCommand"):
                    e["default"] = STUB
                elif k in ("bar.logo.items", "bar.appMenu.items"):
                    for a in e["default"]:
                        if "command" in a:
                            a["command"] = STUB
                elif k == "shelf.folder":
                    e["default"] = shelf
                elif k == "shelf.keepScreenshots":
                    e["default"] = False
    open(path, "w").write(json.dumps(schema, indent=2, ensure_ascii=False))
    # the user's own overrides would win over the stubs: the copy runs on the schema's values only
    open(os.path.join(dest, "config", "config.jsonc"), "w").write('{\n    "$schema": "./config.schema.json"\n}\n')

    # ---- Sys: no sounds, no wallpaper changes, no opening files / links ----
    sys_path = os.path.join(dest, "services", "Sys.qml")
    s = open(sys_path).read()
    for fn in ("playSound", "setWallpaper", "openFile", "openUrl", "revealFile", "copyText", "setAudioOutput", "setVolume", "toggleMute", "toggleMicMute", "setBrightness"):
        s, n = re.subn(r"(    function " + fn + r"\([^)]*\) \{\n)", r"\1        console.warn('TEST " + fn + r" (stubbed)');\n        return;\n", s, count=1)
        if n != 1:
            sys.exit(f"scratch-copy: Sys.{fn} not found")
    open(sys_path, "w").write(s)

    # ---- shell.qml: no keyboard, no reserved space, a grabbable scene, the tester ----
    shell_path = os.path.join(dest, "shell.qml")
    q = open(shell_path).read()
    q, n1 = re.subn(r"        exclusiveZone: Config\.bar\.height\n", "        exclusiveZone: 0\n", q)
    q, n2 = re.subn(r"        WlrLayershell\.keyboardFocus: .*\n", "        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None\n", q)
    q, n3 = re.subn(r"        Bar \{\n            id: bar", "        Item {\n        id: scene\n        width: topBar.width\n        height: topBar.height\n        Bar {\n            id: bar", q)
    end = "        }\n    }\n\n    // click outside"
    n4 = q.count(end)
    q = q.replace(end, "        }\n        }\n" + ("        Tester {}\n" if tester else "") + "    }\n\n    // click outside")
    if (n1, n2, n3, n4) != (1, 1, 1, 1):
        sys.exit(f"scratch-copy: shell.qml changed shape ({n1}, {n2}, {n3}, {n4}): update this tool")
    open(shell_path, "w").write(q)
    if tester:
        shutil.copy2(tester, os.path.join(dest, "Tester.qml"))

    print(f"test copy ready: qs -p {dest}")
    print(f"shelf folder: {shelf}")


if __name__ == "__main__":
    main()
