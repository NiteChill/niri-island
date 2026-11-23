import QtQuick

import "../services"

// A toggle switch for a dropdown's header (Wi-Fi, Bluetooth): a round knob on a capsule track, the accent
// when on, a soft tint of the text color when off (panel.switch.*). The knob slides on a spring; a click or
// Space (the dropdown's own key handling) flips it.
Item {
    id: sw

    property bool checked: false
    signal toggled

    readonly property var look: Config.panel.switch
    implicitWidth: look.width
    implicitHeight: look.height

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? Config.colors.accent : Qt.alpha(palette.windowText, sw.look.offOpacity)
        Behavior on color {
            ColorAnimation {
                duration: Config.motion.colorFade
            }
        }
    }
    Rectangle {
        id: knob
        width: sw.height - 2 * sw.look.inset
        height: width
        radius: width / 2
        y: sw.look.inset
        x: sw.checked ? sw.width - width - sw.look.inset : sw.look.inset
        color: sw.look.knobColor
        Behavior on x {
            SpringAnimation {
                spring: Config.spring(sw.look.spring).spring
                damping: Config.spring(sw.look.spring).damping
                epsilon: 0.25
            }
        }
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: sw.toggled()
    }
}
