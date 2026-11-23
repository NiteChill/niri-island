import QtQuick

import "../services"

// The highlight behind a list's selected row, the one rule every list follows (the lists' look:
// panel.list.highlight / selectedOpacity): it springs from row to row while shown, fades out in place when
// nothing is lit (it keeps its row: dropping to the first one slid it up while fading), and when it shows
// again it jumps to its row instead of sliding from where it last was. The list gives it the row's top
// (`rowY`) and whether a row is lit (`shown`); it keeps the last lit row's place by itself.
Rectangle {
    id: wash

    property real rowY: 0
    property bool shown: false

    // the place of the last lit row (only follows rowY while shown)
    property real at: 0
    onRowYChanged: if (shown)
        at = rowY
    onShownChanged: if (shown)
        at = rowY

    width: parent ? parent.width : 0
    radius: Config.corner("row", height)
    color: palette.windowText
    opacity: shown ? Config.panel.list.selectedOpacity : 0
    visible: opacity > 0
    y: at
    Behavior on y {
        enabled: wash.visible
        SpringAnimation {
            spring: Config.spring(Config.panel.list.highlight).spring
            damping: Config.spring(Config.panel.list.highlight).damping
            epsilon: 0.25
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: Config.motion.hoverFade
        }
    }
}
