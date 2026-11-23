import QtQuick
import QtQuick.Window

import "../services"

// Classic battery icon in the battery color: bright up to the level, dim after it.
// The level spans the whole icon, tip included (the tip lights up last).
// The body's flat top and bottom are snapped to device pixels (scale nudged so its height is whole
// pixels, then shifted onto the pixel grid): otherwise, at fractional scales (1.25), the half-covered
// rows above and below it read as thin dark bars.
// The bar (white) and the charging alert (which sets `level` to animate the fill).
Item {
    id: battery

    // config
    readonly property var icon: Config.bar.battery

    // the battery color by default; the bar passes white
    property color tint: Sys.battery.color
    readonly property color iconColor: tint
    // 0 - 1; defaults to the real level
    property real level: Sys.battery.level

    // the body, in viewBox units: the widest subpath of the icon (whole viewBox if it can't be told).
    // Only used to snap its top and bottom to pixels.
    readonly property var body: {
        const g = batBase.glyph;
        if (!g)
            return null;
        let best = null;
        for (const p of g.parts || [])
            if (!best || p.w > best.w)
                best = p;
        return best && best.w > 0 && best.h > 0 ? best : {
            "x": g.x,
            "y": g.y,
            "w": g.w,
            "h": g.h
        };
    }

    // ---- pixel snapping ----
    // the window's own ratio (1.25 on a 1.25 output; Screen.devicePixelRatio says 2 there)
    readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
    // the icon's own scale fitted in its box (as Icon would fit it), then nudged so the body's height is
    // whole device pixels
    readonly property real fitK: Math.min(icon.size / batBase.gw, height / batBase.gh)
    readonly property real k: body ? Math.max(1, Math.round(body.h * fitK * dpr)) / (body.h * dpr) : fitK
    // this item's top in the window, ignoring transforms (the island's transitions scale its content
    // for a moment; at rest there are none). Updated by snap().
    property real sceneTop: 0
    // vertical shift that puts the body's top on a device pixel
    readonly property real dy: {
        if (!body)
            return 0;
        const top = (sceneTop + batBase.y + batBase.oy + body.y * k) * dpr;
        return (Math.round(top) - top) / dpr;
    }
    function snap() {
        let y = 0;
        for (let it = battery; it; it = it.parent)
            y += it.y;
        sceneTop = y;
    }
    Component.onCompleted: Qt.callLater(snap)
    onHeightChanged: Qt.callLater(snap)
    onYChanged: Qt.callLater(snap)
    onDprChanged: Qt.callLater(snap)

    // the drawn icon's height (the snapped scale): what a badge on its end lines up with
    readonly property real drawnHeight: batBase.gh * k

    // where the fill ends, in batBase: the level across the drawn icon (its viewBox), tip included
    readonly property real fillEnd: batBase.ox + batBase.gx * k + batBase.gw * k * Math.max(0, Math.min(1, level))

    // style
    width: icon.size
    height: parent.height
    anchors.verticalCenter: parent.verticalCenter

    // measures only (glyph, snapped scale, offset): the two copies below draw it
    Icon {
        id: batBase

        visible: false
        name: battery.icon.icon
        fixedScale: battery.k
        width: battery.icon.size
        height: battery.height
        anchors.centerIn: battery
    }

    // content: the bright part up to fillEnd, the dim part after it. Each clips its own copy of the icon:
    // a dim copy under the bright one would show its antialiased edges as a dark fringe around the fill.
    // (the clips reach a whole icon width past the box on the outer sides: the snapped scale can draw a hair
    // wider than the box, and its edge must not be cut)
    Item {
        x: batBase.x - batBase.width
        y: batBase.y + battery.dy
        width: batBase.width + battery.fillEnd
        height: battery.height

        clip: true

        Icon {
            x: batBase.width
            name: battery.icon.icon
            color: battery.iconColor
            fixedScale: battery.k

            width: battery.icon.size
            height: battery.height
        }
    }

    Item {
        x: batBase.x + battery.fillEnd
        y: batBase.y + battery.dy
        width: 2 * batBase.width - battery.fillEnd
        height: battery.height

        clip: true
        opacity: Config.bar.overlayOpacity

        Icon {
            x: -battery.fillEnd
            name: battery.icon.icon
            color: battery.iconColor
            fixedScale: battery.k

            width: battery.icon.size
            height: battery.height
        }
    }
}
