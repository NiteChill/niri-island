import QtQuick

import "../services"
import "../island"
import "../widgets"

// Island mode (an activity, put up by Activity): microphone muted / live. Laid out like the iPhone's
// Silent switch: as tall as the resting island, a capsule at the far left (solid red with the crossed
// mic when muted, soft when live; the glyph wiggles on mute) and the state in words at the far right,
// red when muted. Clicking the capsule toggles the mic.
IslandMode {
    id: mode

    readonly property var layout: Config.microphone
    readonly property bool muted: Sys.audio.micMuted
    readonly property real restHeight: island ? island.restHeight : 0

    implicitWidth: layout.width
    implicitHeight: restHeight

    readonly property color tint: muted ? Config.colors.danger : palette.windowText

    // wiggle on mute: once the pop-up is on screen (appeared: the mute itself comes just before the pop-up
    // is put up), or right away when muting while it's already showing
    property real shake: 0
    onMutedChanged: {
        if (muted && hasAppeared)
            shakeAnim.restart();
    }
    onAppeared: {
        if (muted)
            shakeAnim.restart();
    }
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation {
            target: mode
            property: "shake"
            to: 1
            duration: mode.layout.shakeDuration / 4
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: mode
            property: "shake"
            to: -1
            duration: mode.layout.shakeDuration / 2
            easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            target: mode
            property: "shake"
            to: 0
            duration: mode.layout.shakeDuration / 4
            easing.type: Easing.InCubic
        }
    }

    // centred: the island is never narrower than island.minWidth, which can be wider than this pill
    Item {
        x: (mode.width - mode.implicitWidth) / 2
        width: mode.implicitWidth
        height: mode.implicitHeight

        Badge {
            id: badge
            x: Config.activity.inset
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - 2 * Config.activity.inset
            width: mode.layout.badgeWidth
            icon: mode.muted ? mode.layout.mutedIcon : mode.layout.icon
            tint: mode.tint
            solid: mode.muted
            glyphRotation: mode.shake * mode.layout.shakeAngle
            clickable: true
            onClicked: {
                Sys.toggleMicMute();
                Activity.feedback("microphone");
            }
        }

        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: Config.activity.edge
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Config.activity.titleSize
            color: mode.tint
            Behavior on color {
                ColorAnimation {
                    duration: Config.motion.colorFade
                }
            }
            text: mode.muted ? mode.layout.offText : mode.layout.onText
        }
    }
}
