import QtQuick
import QtQuick.Effects
import QtQuick.Window

import "../services"

// A small glyph on the bottom-right corner (or the right end, `centered`) of something, with that thing cut away `gap` around the glyph
// (the idle battery's charging bolt). The cut is an inverted MultiEffect mask: real transparency, so it
// also works on the blurred island; the layer exists only while the badge shows.
// The cut is the glyph grown by `gap` (drawn again, shifted `gap` in 8 directions): right for solid glyphs.
// A hollow glyph (the headphones, tried 2026-11-15) lets the content peek through its hollow: cut its
// filled silhouette instead (e.g. a Rectangle with a dome top), grown by `gap`.
// (The glyph's id isn't `glyph`: Icon has a `glyph` property, so inside the copies `glyph.x` read their own.)
// The layer is what made the content soft: its texture is resampled when it's drawn, so a box that sits
// mid-pixel (or a texture a hair smaller than the box: Qt rounds the logical size before the 1.25 ratio)
// smears every edge, the battery's pixel-snapped ones included. So the layered box is put on the device
// pixel grid, with a texture exactly its size in device pixels, and the content is shifted back inside it
// (it lands where it would without the badge).
// The content goes inside; it's laid out in a box contentWidth wide, the item's height, and the glyph's
// corner is placed against a contentWidth x contentHeight box centred in it.
Item {
    id: badge

    property bool shown: false
    property string icon
    property color color: Config.colors.text
    property real size
    property real overhangX       // past the content's right edge
    property real overhangY       // below the content's bottom (ignored when `centered`)
    property bool centered: false  // vertically centred on the content instead
    property real gap             // the cut around the glyph
    property real contentWidth
    property real contentHeight
    default property alias content: holder.data

    implicitWidth: contentWidth + (shown ? overhangX : 0)

    // appearing: the glyph (and its cut, together) fades in over fadeDuration and springs up from popFrom
    // with a little bounce (popSpring); leaving: fades out, shrinking back
    property real fadeDuration: Config.idle.battery.badge.fade
    property real popFrom: Config.idle.battery.badge.popFrom
    property var popSpring: Config.idle.battery.badge.pop
    property real level: shown ? 1 : 0
    Behavior on level {
        NumberAnimation {
            duration: badge.fadeDuration
            easing.type: Easing.OutCubic
        }
    }
    property real pop: shown ? 1 : 0
    Behavior on pop {
        SpringAnimation {
            spring: Config.spring(badge.popSpring).spring
            damping: Config.spring(badge.popSpring).damping
            epsilon: 0.001
        }
    }
    readonly property real glyphScale: Math.max(0, popFrom + (1 - popFrom) * pop)

    // ---- the layer on the pixel grid ----
    // the window's own ratio (Screen.devicePixelRatio says 2 on the 1.25 output)
    readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
    readonly property bool layered: level > 0 || shown
    // this item's position in the window, ignoring transforms (at rest there are none). Only followed
    // while the layer exists.
    readonly property point scenePos: {
        if (!layered)
            return Qt.point(0, 0);
        let x = 0, y = 0;
        for (let it = badge; it; it = it.parent) {
            x += it.x;
            y += it.y;
        }
        return Qt.point(x, y);
    }
    // how far past a device pixel the item starts: the layered box starts that much earlier
    readonly property real fracX: (scenePos.x * dpr - Math.floor(scenePos.x * dpr)) / dpr
    readonly property real fracY: (scenePos.y * dpr - Math.floor(scenePos.y * dpr)) / dpr
    // the box in whole device pixels
    readonly property int texW: Math.ceil((contentWidth + fracX) * dpr)
    readonly property int texH: Math.ceil((height + fracY) * dpr)

    Item {
        id: inner
        x: -badge.fracX
        y: -badge.fracY
        width: badge.texW / badge.dpr
        height: badge.texH / badge.dpr
        layer.enabled: badge.layered
        layer.textureSize: Qt.size(badge.texW, badge.texH)
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: knockout
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        // the content, back where it belongs
        Item {
            id: holder
            x: badge.fracX
            y: badge.fracY
            width: badge.contentWidth
            height: badge.height
        }
    }
    Item {
        id: knockout
        x: inner.x
        y: inner.y
        width: inner.width
        height: inner.height
        visible: false
        layer.enabled: badge.layered
        layer.textureSize: inner.layer.textureSize
        // (the fade on a child: a layer leaves out its own item's opacity)
        Item {
            x: badge.fracX
            y: badge.fracY
            width: badge.contentWidth
            height: badge.height
            opacity: badge.level
            Repeater {
                model: 8
                delegate: Icon {
                    required property int index
                    readonly property real turn: index * Math.PI / 4
                    x: mark.x + Math.cos(turn) * badge.gap
                    y: mark.y + Math.sin(turn) * badge.gap
                    width: mark.width
                    height: mark.height
                    scale: badge.glyphScale
                    name: badge.icon
                    color: Config.colors.text
                }
            }
        }
    }
    Icon {
        id: mark
        x: badge.contentWidth + badge.overhangX - width
        y: badge.centered ? (badge.height - height) / 2 : (badge.height + badge.contentHeight) / 2 + badge.overhangY - height
        width: badge.size
        height: badge.size
        name: badge.icon
        color: badge.color
        opacity: badge.level
        scale: badge.glyphScale
        visible: opacity > 0
    }
}
