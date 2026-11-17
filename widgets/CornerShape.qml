import QtQuick
import QtQuick.Shapes

import "../services"

// One rounded screen corner (config screenCorners): paints the area outside a corner of radius
// screenCorners.radius, smoothed like the island's (screenCorners.smoothing: the curve starts further
// along the edges and blends into them; Config.screenCorner), drawn for the top-left corner in a `size`
// square (Config.screenCorner.p); `rotation` (multiples of 90) turns it into the others.
// Used by ScreenCorners (one overlay window per corner).
Shape {
    id: corner

    property real size: Config.screenCorner.p

    width: size
    height: size
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeWidth: -1
        fillColor: Config.screenCorners.color
        // the straight sides start one pixel past the edges, so edge antialiasing never leaves a faint
        // line along the screen border (the overflow is clipped by the window). The curve runs from the
        // left edge (0, size) up to the top edge (size, 0).
        PathSvg {
            path: {
                const q = Config.screenCorner, n = v => v.toFixed(2);
                return "M -1 " + n(q.p) + " L 0 " + n(q.p) + Config.cornerSvg(q, 3) + " L " + n(q.p) + " -1 L -1 -1 Z";
            }
        }
    }
}
