pragma Singleton
import QtQuick
import Quickshell

// The frosted surfaces (panel.blur: the dropdown card, the notification cards and the history's chips):
// each widgets/Frost registers itself here, and shell.qml asks niri to blur behind every one that's shown
// (BackgroundEffect.blurRegion, one Region per rectangle). The notch stays solid black on purpose: it
// pretends to be the screen's own notch.
Singleton {
    id: root

    // the Frost items alive now
    property var surfaces: []
    function add(frost) {
        surfaces = surfaces.concat([frost]);
    }
    function remove(frost) {
        surfaces = surfaces.filter(s => s !== frost);
    }
    // what niri blurs: { x, y, w, h, r } in the window, for each surface shown
    readonly property var rects: surfaces.filter(s => s.shown && s.rect.width > 0 && s.rect.height > 0).map(s => ({
                "x": Math.round(s.rect.x),
                "y": Math.round(s.rect.y),
                "w": Math.round(s.rect.width),
                "h": Math.round(s.rect.height),
                "r": Math.round(s.radius)
            }))
}
