import QtQuick
import QtQuick.Shapes

import "../services"

// Monochrome icon from assets/icons, drawn as a vector path (Config.glyph): sharp at any size and screen
// scale, tinted by `color` (bindable, animatable). Fits inside its box keeping the SVG's proportions, centred.
// Icon files may only use <path> elements, without transforms (tools/check-config.py enforces it).
Item {
    id: icon

    // icon file name from the config (e.g. "wifi3.svg"); empty = draws nothing
    property string name
    property color color: Config.colors.text
    // viewBox units -> pixels, when the user of the icon picks it (e.g. Battery snapping to device pixels);
    // 0 = fit the box
    property real fixedScale: 0

    readonly property var glyph: Config.glyph(name)
    readonly property real gx: glyph ? glyph.x : 0
    readonly property real gy: glyph ? glyph.y : 0
    readonly property real gw: glyph ? glyph.w : 1
    readonly property real gh: glyph ? glyph.h : 1
    // viewBox units -> pixels
    readonly property real k: fixedScale > 0 ? fixedScale : Math.min(width / gw, height / gh)
    // where the viewBox's corner is drawn, in this item (the drawing is centred in the box)
    readonly property real ox: (width - gw * k) / 2 - gx * k
    readonly property real oy: (height - gh * k) / 2 - gy * k

    Shape {
        visible: !!icon.glyph
        // the path is drawn in viewBox coordinates: shift so the viewBox's corner lands on the fitted box
        x: icon.ox
        y: icon.oy
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: icon.color
            strokeColor: "transparent"
            strokeWidth: 0
            fillRule: icon.glyph && icon.glyph.evenOdd ? ShapePath.OddEvenFill : ShapePath.WindingFill
            scale: Qt.size(icon.k, icon.k)
            PathSvg {
                path: icon.glyph ? icon.glyph.path : ""
            }
        }
    }
}
