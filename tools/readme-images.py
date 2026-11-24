#!/usr/bin/env python3
"""Make the README's pictures (docs/*.png) from the real shell, staged with made-up data.

    python3 tools/readme-images.py

A test copy (tools/scratch-copy.py: nothing runs, no keyboard, no reserved space) is staged so that
nothing private shows: a fixed clock (Tuesday 9 June, 9:41), "Home" Wi-Fi, "Buds" headphones,
"Speakers" / "Buds" outputs, a made-up song, made-up notifications, generated pictures on the shelf, no
tray icons, "Files" as the focused app, no alerts of its own. It runs on screen for ~30 s (shapes and
effects only render on the GPU), opens each state, grabs it at 2x and composes it over a generated
wallpaper:
  docs/hero.png    the bar, the music in the notch, quick settings open
  docs/panels.png  notifications, the calendar with the history, search, the player
  docs/shelf.png   the shelf
Run it again whenever the shell's look changes. Needs Pillow (python3-pillow).
"""
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
SCALE = 2
# what's grabbed, in order: (name, what the tester does)
SCENES = ["hero", "notifications", "calendar", "search", "player", "shelf"]


def patch(path, old, new):
    s = open(path, encoding="utf-8").read()
    if s.count(old) != 1:
        sys.exit(f"readme-images: can't stage {os.path.basename(path)}: {old[:70]!r} found {s.count(old)} times")
    open(path, "w", encoding="utf-8").write(s.replace(old, new))


def field(path, size, palette, seed):
    """A soft, blurred colour field (a wallpaper, a cover, a picture)."""
    w, h = max(8, size[0] // 8), max(8, size[1] // 8)
    im = Image.new("RGB", (w, h))
    px = im.load()
    rnd = random.Random(seed)
    blobs = [(rnd.random() * w, rnd.random() * h, palette[rnd.randint(1, len(palette) - 1)]) for _ in range(5)]
    for y in range(h):
        for x in range(w):
            t = y / h
            c = [palette[0][k] * (1 - t) + palette[1][k] * t for k in range(3)]
            for bx, by, col in blobs:
                d = math.exp(-((x - bx) ** 2 + (y - by) ** 2) / (2 * (w / 4.5) ** 2))
                c = [c[k] * (1 - d) + col[k] * d for k in range(3)]
            px[x, y] = tuple(int(v) for v in c)
    im = im.resize(size, Image.BICUBIC).filter(ImageFilter.GaussianBlur(max(2, size[0] // 90)))
    im.save(path, quality=92)
    return path


PALETTES = [
    [(34, 40, 92), (190, 96, 140), (250, 160, 110), (90, 140, 220)],   # the wallpaper: dusk
    [(255, 150, 92), (194, 69, 122), (250, 210, 120)],                  # the cover
    [(90, 200, 250), (88, 86, 214), (180, 230, 255)],                   # an avatar
    [(20, 70, 90), (60, 160, 150), (220, 235, 200)],                    # shelf pictures...
    [(70, 30, 60), (220, 110, 90), (255, 220, 150)],
    [(25, 30, 45), (90, 110, 160), (200, 210, 235)],
    [(40, 80, 40), (140, 190, 100), (245, 235, 170)],
]


def stage(work, pics):
    sys_qml = os.path.join(work, "services", "Sys.qml")
    patch(sys_qml, "    readonly property date time: clock.date ? clock.date : new Date()",
          "    readonly property date time: new Date(2026, 5, 9, 9, 41)")
    patch(sys_qml, '"ssid": _wifiActive ? (_wifiActive.ssid || _wifiActive.name || "") : "",', '"ssid": _wifiActive ? "Home" : "",')
    patch(sys_qml, '"name": _wifiActive ? (_wifiActive.name || "") : "",', '"name": _wifiActive ? "Home" : "",')
    patch(sys_qml, '"name": connected.length > 0 ? connected[0].name : "",', '"name": connected.length > 0 ? "Buds" : "",')
    patch(sys_qml, '"description": n.description || n.nickname || n.name,', '"description": !!def && def.name === n.name ? "Buds" : "Speakers",')
    patch(sys_qml, "    readonly property var trayItems: SystemTray.items.values", "    readonly property var trayItems: []")
    patch(sys_qml, "    readonly property var media: {", """    // the made-up song, from the start: the real one never shows
    property bool demoPlaying: true
    readonly property var media: demoPlaying ? ({
            "active": true, "playing": true, "title": "Golden Hour Drive", "artist": "Neon Coast", "album": "",
            "app": "Music", "artUrl": "file://%s", "length": 223, "canPlayPause": true, "canNext": true,
            "canPrevious": true, "canSeek": true
        }) : _realMedia
    readonly property var _realMedia: {""" % pics["cover"])
    patch(sys_qml, "    function mediaPositionNow() {", "    function mediaPositionNow() {\n        if (demoPlaying)\n            return 83;")
    patch(sys_qml, "    readonly property bool mediaFocused: {",
          "    readonly property bool mediaFocused: demoPlaying ? false : _realMediaFocused\n    readonly property bool _realMediaFocused: {")
    patch(sys_qml, "    readonly property real mediaRate: _anchorRate", "    readonly property real mediaRate: demoPlaying ? 0 : _anchorRate")
    # only what the script shows: no alerts from the real computer (the music's base layer and panels pass)
    patch(os.path.join(work, "services", "Activity.qml"), "    function show(kind, key, cls, data, timeout) {",
          "    function show(kind, key, cls, data, timeout) {\n        if (cls !== \"nowPlaying\" && cls !== \"panel\")\n            return;")
    patch(os.path.join(work, "modes", "SearchMode.qml"), "    readonly property var layout: Config.search",
          "    readonly property var layout: Config.search\n    readonly property var demoInput: input")

    path = os.path.join(work, "config", "schema.json")
    schema = json.load(open(path))
    values = {"bar.hideInFullscreen": False, "media.bars.realSound": False, "wallpaper.folders": [pics["walls"]]}
    for section in schema["sections"]:
        for group in section["groups"]:
            for e in group["settings"]:
                if e["key"] in values:
                    e["default"] = values[e["key"]]
    open(path, "w").write(json.dumps(schema, indent=2, ensure_ascii=False))


TESTER = r"""import QtQuick
import "services"

// readme-images.py: each scene, settled, grabbed at %(scale)dx
Item {
    id: t
    readonly property var scenes: %(scenes)s
    property int index: -1
    property var searchMode: null
    function findSearch(item) {
        if (item.demoInput !== undefined)
            return item;
        for (let i = 0; i < item.children.length; i++) {
            const f = findSearch(item.children[i]);
            if (f)
                return f;
        }
        return null;
    }
    function notes() {
        const now = Sys.time.getTime();
        const rows = [
            ["Messages", "Alex", "Dinner at 8? I booked the place by the river.", "%(avatar)s", 0],
            ["Calendar", "Design review", "In 15 minutes, room 2", "", 4],
            ["Mail", "Your trip to Lisbon", "Here are the tickets and the hotel booking. Have a good one!", "", 52]
        ];
        for (let i = rows.length - 1; i >= 0; i--)
            Inbox._insert({ "uid": "demo" + i, "kind": "notification", "nid": -1, "app": rows[i][0], "entry": "", "icon": "",
                "image": rows[i][3], "summary": rows[i][1], "body": rows[i][2], "urgency": "normal",
                "time": now - rows[i][4] * 60000, "pile": "", "width": 0, "height": 0, "section": "new", "leaving": false });
    }
    function setUp(name) {
        Sys.focusedApp = "Files";
        if (name === "hero")
            Activity.open("quickSettings");
        else if (name === "notifications") {
            Activity.closeAll();
            Inbox._showBanner("demo0", 600000);
            Inbox._showBanner("demo1", 600000);
        } else if (name === "calendar")
            Activity.open("calendar");
        else if (name === "search") {
            Activity.open("search");
            Qt.callLater(() => {
                t.searchMode = t.findSearch(scene);
                if (t.searchMode)
                    t.searchMode.demoInput.text = "%(query)s";
            });
        } else if (name === "player")
            Activity.open("media");
        else if (name === "shelf")
            Activity.open("shelf");
        Qt.callLater(() => console.warn("DEMO-STATE", name, Sys.media.title, Activity.current ? Activity.current.kind : "-"));
    }
    Component.onCompleted: notes()
    // one scene every 2.2 s: grab it, and only once the grab is saved, set up the next one (changing
    // the state in the same handler as the grab captured the new state)
    function next() {
        t.index++;
        if (t.index >= t.scenes.length) {
            console.warn("DEMO-END");
            Qt.quit();
            return;
        }
        t.setUp(t.scenes[t.index]);
        tick.restart();
    }
    Timer {
        id: tick
        interval: 2200
        running: true
        onTriggered: {
            Sys.focusedApp = "Files";
            if (t.index < 0) {
                t.next();
                return;
            }
            const name = t.scenes[t.index];
            // the frosted surfaces (panel.blur, Glass): where niri would blur, for the composition
            const glass = Glass.rects.map(g => [g.x, g.y, g.w, g.h, g.r].join(",")).join(";");
            scene.grabToImage(r => {
                r.saveToFile("%(out)s/" + name + ".png");
                console.warn("DEMO-SHOT " + name + " GLASS " + glass);
                t.next();
            }, Qt.size(scene.width * %(scale)d, scene.height * %(scale)d));
        }
    }
}
"""


# niri's blur behind the frosted surfaces (2 passes, offset 2: about this Gaussian radius, logical px)
BLUR = 6


def over(wall, shot, glass=()):
    w = Image.open(wall).convert("RGBA").resize(shot.size, Image.BICUBIC)
    # the frosted surfaces (dropdowns, notification cards): the wallpaper blurred under them, as niri does
    # on screen (a grab can't see it)
    if glass:
        mask = Image.new("L", w.size, 0)
        draw = ImageDraw.Draw(mask)
        for x, y, cw, ch, r in glass:
            draw.rounded_rectangle((x * SCALE, y * SCALE, (x + cw) * SCALE, (y + ch) * SCALE), r * SCALE, fill=255)
        w = Image.composite(w.filter(ImageFilter.GaussianBlur(BLUR * SCALE)), w, mask)
    w.alpha_composite(shot)
    return w.convert("RGB")


def rounded(im, r):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), r, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def main():
    work = tempfile.mkdtemp(prefix="readme-images-")
    try:
        pics = {"walls": os.path.join(work, "walls"), "cover": os.path.join(work, "cover.jpg"), "avatar": os.path.join(work, "avatar.png")}
        shelf = os.path.join(work, "shelf")
        os.makedirs(pics["walls"])
        os.makedirs(shelf)
        wall = field(os.path.join(pics["walls"], "dusk.jpg"), (1920, 1200), PALETTES[0], 1)
        field(pics["cover"], (256, 256), PALETTES[1], 2)
        field(os.path.join(work, "a.png"), (128, 128), PALETTES[2], 3)
        av = Image.open(os.path.join(work, "a.png")).convert("RGBA")
        mask = Image.new("L", av.size, 0)
        ImageDraw.Draw(mask).ellipse((0, 0, av.width - 1, av.height - 1), fill=255)
        av.putalpha(mask)
        av.save(pics["avatar"])
        for n, pal in enumerate(PALETTES[3:]):
            field(os.path.join(shelf, f"Photo {n + 1}.jpg"), (1200, 800), pal, 10 + n)
            # the shelf sorts by date: oldest first here, so "Photo 1" ends up in front
            os.utime(os.path.join(shelf, f"Photo {n + 1}.jpg"), (1_780_000_000 - n * 60, 1_780_000_000 - n * 60))

        shots = os.path.join(work, "shots")
        os.makedirs(shots)
        tester = os.path.join(work, "T.qml")
        open(tester, "w").write(TESTER % {"scale": SCALE, "scenes": json.dumps(SCENES), "avatar": pics["avatar"],
                                          "out": shots, "query": "night"})
        copy = os.path.join(work, "copy")
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "scratch-copy.py"), copy, "--tester", tester, "--shelf", shelf],
                       check=True, stdout=subprocess.DEVNULL)
        stage(copy, pics)

        # the copy keeps its history in a state folder of its own: the new one is removed afterwards
        states = os.path.expanduser("~/.local/state/quickshell/by-shell")
        before = set(os.listdir(states)) if os.path.isdir(states) else set()
        log = os.path.join(work, "run.log")
        with open(log, "w") as f:
            subprocess.run(["timeout", "-s", "TERM", "40", "qs", "-p", copy], stdout=f, stderr=subprocess.STDOUT)
        text = open(log, encoding="utf-8", errors="replace").read()
        for d in (set(os.listdir(states)) - before) if os.path.isdir(states) else ():
            shutil.rmtree(os.path.join(states, d), ignore_errors=True)
        done = set(re.findall(r"DEMO-SHOT (\w+)", text))
        if "DEMO-END" not in text or done != set(SCENES):
            shutil.copy(log, os.path.join(ROOT, "readme-images.log"))
            sys.exit("readme-images: not every scene was captured; see readme-images.log")

        glass = {m.group(1): [[int(v) for v in r.split(",")] for r in m.group(2).split(";") if r]
                 for m in re.finditer(r"DEMO-SHOT (\w+) GLASS ([-\d,;]*)", text)}
        g = {n: over(wall, Image.open(os.path.join(shots, n + ".png")).convert("RGBA"), glass.get(n, ())) for n in SCENES}
        W = g["hero"].width
        bar_h = 38 * SCALE

        def right(im, w, h):
            return im.crop((im.width - w, 0, im.width, h))

        def middle(im, w, h):
            return im.crop(((im.width - w) // 2, 0, (im.width + w) // 2, h))

        os.makedirs(DOCS, exist_ok=True)
        # the hero: the whole width, down to under quick settings
        g["hero"].crop((0, 0, W, 400 * SCALE)).save(os.path.join(DOCS, "hero.png"), optimize=True)
        # the panels: four tiles in a 2 x 2 grid
        tw, th = 760 * SCALE, 560 * SCALE
        tiles = [right(g["notifications"], tw, th), right(g["calendar"], tw, th), middle(g["search"], tw, th), middle(g["player"], tw, th)]
        gap = 24 * SCALE
        grid = Image.new("RGBA", (2 * tw + 3 * gap, 2 * th + 3 * gap), (0, 0, 0, 0))
        for i, tile in enumerate(tiles):
            grid.alpha_composite(rounded(tile, 18 * SCALE), (gap + (i % 2) * (tw + gap), gap + (i // 2) * (th + gap)))
        grid.save(os.path.join(DOCS, "panels.png"), optimize=True)
        middle(g["shelf"], 1000 * SCALE, 330 * SCALE).save(os.path.join(DOCS, "shelf.png"), optimize=True)
        print("readme-images: docs/hero.png, docs/panels.png, docs/shelf.png")
    finally:
        if os.environ.get("README_IMAGES_KEEP"):
            print("readme-images: kept", work)
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
