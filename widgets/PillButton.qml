import QtQuick

import "../services"

// A labelled toggle in a capsule (the battery panel's "Power saver"): an icon and a word, soft (the tint at
// activity.badgeOpacity, brighter under the pointer) or solid ("this is on": filled with the tint, icon and
// text in `onColor`). Sinks a little when pressed. The round Badge's sibling for when a word says more than
// an icon alone. Settings: panel.button.
Rectangle {
    id: button

    property string icon
    property string text
    property color tint: Config.colors.text
    property bool solid: false
    property color onColor: Config.island.color
    signal clicked

    readonly property var cfg: Config.panel.button
    readonly property color ink: solid ? onColor : tint

    // the icon side gets less padding than the text side: the icon is visually heavier, so equal padding
    // looks lopsided (optical centring)
    readonly property real leading: icon !== "" ? cfg.iconPadding : cfg.padding
    width: leading + row.width + cfg.padding
    height: cfg.height
    radius: Config.corner("pill", height)
    color: solid ? tint : Qt.alpha(tint, hover.hovered ? Config.activity.badgeHoverOpacity : Config.activity.badgeOpacity)
    Behavior on color {
        ColorAnimation {
            duration: Config.motion.colorFade
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
        x: button.leading
        anchors.verticalCenter: parent.verticalCenter
        spacing: button.cfg.gap
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.icon !== ""
            width: button.cfg.iconSize
            height: button.cfg.iconSize
            name: button.icon
            color: button.ink
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: button.cfg.textSize
            color: button.ink
            text: button.text
            Behavior on color {
                ColorAnimation {
                    duration: Config.motion.colorFade
                }
            }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: tap
        onTapped: button.clicked()
    }
}
