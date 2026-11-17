import QtQuick
import QtQuick.Shapes

import "../services"

// The panels' gauge (battery level, the time of day): a thick band bent into a gentle arc, filled in `tint`
// from its left end up to `value` with the band's own rounded ends (1 covers it exactly, a sliver is a
// short rounded bit at the start; the ends' corners follow the corner style's `pill` role: half circles in
// Round / Full, softened corners in Soft / Square), chunky ticks across it (cut into the fill, grey on the empty part, every
// `majorEvery`th brighter). Each time `active` turns on, the fill springs up from 0 after
// panel.arc.sweepDelay (once the panel has faded in); later changes spring from where it is. The look is
// shared (panel.arc); the panel picks the tick count.
Item {
    id: gauge

    // ---- in ----
    property real value: 0             // 0 - 1
    property color tint: Config.colors.accent
    property bool active: false        // the panel is open: replays the sweep from 0
    property int ticks: 2
    property int majorEvery: 1

    readonly property var cfg: Config.panel.arc

    // the band: its middle `bend` px above its ends, its rounded ends kept inside the width
    readonly property real thickness: cfg.thickness
    implicitHeight: Math.max(1, cfg.bend) + thickness

    // ---- the sweep ----
    property real shown: value
    readonly property real level: Math.max(0, Math.min(1, shown))
    Behavior on shown {
        id: sweepAnim
        SpringAnimation {
            spring: Config.spring(gauge.cfg.sweepSpring).spring
            damping: Config.spring(gauge.cfg.sweepSpring).damping
            epsilon: 0.0005
        }
    }
    onActiveChanged: {
        if (!active)
            return;
        sweepAnim.enabled = false;
        shown = 0;
        sweepAnim.enabled = true;
        sweepDelay.restart();
    }
    Timer {
        id: sweepDelay
        interval: gauge.cfg.sweepDelay
        onTriggered: gauge.shown = Qt.binding(() => gauge.value)
    }

    // ---- geometry: the band's centre line is a circle arc through both ends ----
    // corner of the band's ends (island.shape's pill role, at most half the thickness). Whatever the
    // corner, the band reaches half its thickness past each end of its centre line (where the end ticks
    // sit), so the end ticks keep the same room in every style
    readonly property real endCorner: Config.corner("pill", thickness)
    readonly property real endReach: thickness / 2
    readonly property real chord: width - 2 * endReach
    readonly property real bend: Math.max(1, cfg.bend)
    readonly property real radius: (chord * chord / 4 + bend * bend) / (2 * bend)
    readonly property real halfAngle: Math.asin(Math.min(1, chord / 2 / radius))
    readonly property real cx: width / 2
    readonly property real cy: thickness / 2 + radius
    readonly property real degrees: 180 / Math.PI
    // how far each end reaches past its centre line, as an angle and as a level
    readonly property real endAngle: endReach / radius
    readonly property real capLevel: endAngle / (2 * halfAngle)
    // angle (radians, 0 = straight up) for a level 0 - 1
    function angle(level) {
        return (level * 2 - 1) * halfAngle;
    }

    // SVG outline of the band from angle a0 to a1 (its ends included): outer arc, rounded corner, end,
    // rounded corner, inner arc back, and the same at the start. Each corner is a circle touching the
    // arc and the end (exact on the curved band). A piece too short for its corners gets smaller corners.
    function band(a0, a1) {
        const ro = radius + thickness / 2, ri = Math.max(0, radius - thickness / 2);
        const half = Math.sin((a1 - a0) / 2);
        let c = Math.min(endCorner, half * ro / (1 + half), half < 1 ? half * ri / (1 - half) : endCorner);
        c = Math.max(0, c);
        const pt = (a, r) => (cx + r * Math.sin(a)).toFixed(2) + " " + (cy - r * Math.cos(a)).toFixed(2);
        const n = v => v.toFixed(2);
        if (c <= 0)
            return "M " + pt(a0, ro) + " A " + n(ro) + " " + n(ro) + " 0 0 1 " + pt(a1, ro) + " L " + pt(a1, ri)
                + " A " + n(ri) + " " + n(ri) + " 0 0 0 " + pt(a0, ri) + " Z";
        const po = ro - c, pi = ri + c;
        const dO = Math.asin(Math.min(1, c / po)), dI = Math.asin(Math.min(1, c / pi));
        const lo = po * Math.cos(dO), li = pi * Math.cos(dI);
        const k = " A " + n(c) + " " + n(c) + " 0 0 1 ";
        return "M " + pt(a0 + dO, ro)
            + " A " + n(ro) + " " + n(ro) + " 0 0 1 " + pt(a1 - dO, ro)
            + k + pt(a1, lo) + " L " + pt(a1, li) + k + pt(a1 - dI, ri)
            + " A " + n(ri) + " " + n(ri) + " 0 0 0 " + pt(a0 + dI, ri)
            + k + pt(a0, li) + " L " + pt(a0, lo) + k + pt(a0 + dO, ro) + " Z";
    }
    readonly property string trackPath: width > 0 ? band(angle(0) - endAngle, angle(1) + endAngle) : ""
    // rebuilt on every frame of the sweep (only while the panel is open and the level moves)
    readonly property string fillPath: width > 0 && level > 0 ? band(angle(0) - endAngle, angle(level) + endAngle) : ""

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // empty band
        ShapePath {
            fillColor: Qt.alpha(Config.colors.text, gauge.cfg.trackOpacity)
            strokeColor: "transparent"
            PathSvg {
                path: gauge.trackPath
            }
        }
        // the fill: the band from its start to the level, the same rounded ends
        ShapePath {
            fillColor: gauge.tint
            strokeColor: "transparent"
            PathSvg {
                path: gauge.fillPath
            }
        }
    }

    // the ticks: rounded bars across the band, turned to follow it
    Repeater {
        model: gauge.ticks
        delegate: Rectangle {
            required property int index
            readonly property real at: index / Math.max(1, gauge.ticks - 1)
            readonly property real a: gauge.angle(at)
            readonly property bool major: index % gauge.majorEvery === 0
            // under the fill, rounded end included (none while it's empty: the first tick stays grey)
            readonly property bool charged: gauge.level > 0 && at <= gauge.level + gauge.capLevel
            x: gauge.cx + gauge.radius * Math.sin(a) - width / 2
            y: gauge.cy - gauge.radius * Math.cos(a) - height / 2
            rotation: a * gauge.degrees
            width: gauge.cfg.tickWidth
            height: gauge.cfg.tickLength
            radius: width / 2
            antialiasing: true
            color: charged ? Config.island.color : Config.colors.text
            opacity: charged ? gauge.cfg.tickFillOpacity : major ? gauge.cfg.majorTickOpacity : gauge.cfg.tickOpacity
        }
    }
}
