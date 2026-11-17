import QtQuick

import "../services"

// A quick settings switch: a round badge (the activity badges' look: soft when off, solid in the tint when
// on) with one grey word under it, the state ("Ion", "Off", "Muted"). The symbol says what it is, so there's
// no title. Clicking the badge toggles; when the toggle has a panel behind it (`opens`: Wi-Fi, Bluetooth),
// the word is a link to it (white under the pointer). `available` false = dimmed, does nothing.
// The item is one cell of the row: the badge centred on top, the word centred under it (elided to the cell).
// Settings: quickSettings.toggle.
Item {
    id: toggle

    property string icon
    property string word
    property color tint: Config.colors.accent
    property bool on: false
    property bool opens: false
    property bool available: true
    signal toggled
    signal opened

    readonly property var cfg: Config.quickSettings.toggle

    implicitHeight: cfg.badgeSize + cfg.wordGap + label.implicitHeight
    opacity: available ? 1 : cfg.unavailableOpacity

    Badge {
        id: badge
        anchors.horizontalCenter: parent.horizontalCenter
        height: toggle.cfg.badgeSize
        // a free-standing circle: round by meaning, not concentric with anything
        outerCorner: height / 2
        inset: 0
        glyphSize: toggle.cfg.glyphSize
        icon: toggle.icon
        solid: toggle.on
        tint: toggle.on ? toggle.tint : Config.colors.text
        clickable: toggle.available
        onClicked: toggle.toggled()
    }
    StyledText {
        id: label
        anchors.top: badge.bottom
        anchors.topMargin: toggle.cfg.wordGap
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        // often a name (the network, the device): cut in the middle so its end stays
        elide: Text.ElideMiddle
        font.pixelSize: toggle.cfg.wordSize
        color: toggle.opens && wordHover.hovered ? Config.colors.text : Config.colors.secondary
        Behavior on color {
            ColorAnimation {
                duration: Config.motion.hoverFade
            }
        }
        text: toggle.word || ""
        HoverHandler {
            id: wordHover
            enabled: toggle.opens && toggle.available
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: toggle.opens && toggle.available
            onTapped: toggle.opened()
        }
    }
}
