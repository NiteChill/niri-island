import QtQuick

import "../services"

// The soft pill under a panel's symbol that unfolds its list ("Networks · 6 ⌄"): text and an arrow that
// turns over while `expanded`. Brighter under the pointer, sinks a little when pressed. Settings: panel.pill.
Rectangle {
    id: pill

    property string text
    property bool expanded: false
    property bool showArrow: true
    signal clicked

    readonly property var cfg: Config.panel.pill

    width: row.width + 2 * cfg.padding
    height: cfg.height
    radius: Config.corner("pill", height)
    color: Qt.alpha(Config.colors.text, hover.hovered ? cfg.hoverOpacity : cfg.opacity)
    Behavior on color {
        ColorAnimation {
            duration: Config.motion.hoverFade
        }
    }
    scale: tap.pressed ? Config.motion.pressScale : 1
    Behavior on scale {
        NumberAnimation {
            duration: Config.motion.pressDuration
            easing.type: Easing.OutCubic
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: pill.cfg.iconGap
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: pill.cfg.textSize
            color: Config.colors.secondary
            text: pill.text
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.showArrow
            width: pill.cfg.iconSize
            height: pill.cfg.iconSize
            name: pill.cfg.icon
            color: Config.colors.secondary
            rotation: pill.expanded ? 180 : 0
            Behavior on rotation {
                NumberAnimation {
                    duration: Config.motion.settleDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    HoverHandler {
        id: hover
        enabled: pill.showArrow
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: tap
        enabled: pill.showArrow
        onTapped: pill.clicked()
    }
}
