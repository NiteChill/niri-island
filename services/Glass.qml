pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The frosted surfaces (panel.blur: the dropdown card, the notification cards and the history's chips):
// each widgets/Frost registers itself here, and shell.qml asks niri to blur behind every one that's shown
// (BackgroundEffect.blurRegion, one Region per rectangle). The notch stays solid black on purpose: it
// pretends to be the screen's own notch.
// `qs ipc call glass dump` prints what the shell asks niri to blur right now (each surface: shown or not, and
// where): if a blur is left on screen while this says nothing is shown, the stale blur is niri's, not ours.
Singleton {
    id: root

    // the Frost items alive now
    property var surfaces: []
    function add(frost) {
        surfaces = surfaces.concat([frost]);
        changed();
    }
    function remove(frost) {
        surfaces = surfaces.filter(s => s !== frost);
        changed();
    }
    // what niri blurs: { x, y, w, h, r } in the window, for each surface shown. Collected once per event
    // loop turn (Frost calls changed() as it moves) and replaced only when a whole pixel changed: rebuilt
    // on every sub-pixel step of every moving card, it was resent to niri several times a frame (pop-ups
    // sliding in: 149 CPU ticks in 12 s against 112 without the blur, 2026-11-25)
    property var rects: []
    property string _signature: ""
    property bool _pending: false
    function changed() {
        if (_pending)
            return;
        _pending = true;
        Qt.callLater(_refresh);
    }
    function _refresh() {
        _pending = false;
        const next = surfaces.filter(s => s.shown && s.rect.width > 0 && s.rect.height > 0).map(s => ({
                    "x": Math.round(s.rect.x),
                    "y": Math.round(s.rect.y),
                    "w": Math.round(s.rect.width),
                    "h": Math.round(s.rect.height),
                    "r": Math.round(s.radius)
                }));
        const signature = JSON.stringify(next);
        if (signature === _signature)
            return;
        _signature = signature;
        rects = next;
    }

    IpcHandler {
        target: "glass"
        function dump(): string {
            return JSON.stringify({
                "sent": root.rects,
                "surfaces": root.surfaces.map(s => ({
                            "owner": String(s.parent),
                            "shown": s.shown,
                            "visible": s.visible,
                            "opacity": s._here.opacity,
                            "rect": [s.rect.x, s.rect.y, s.rect.width, s.rect.height]
                        }))
            });
        }
    }
}
