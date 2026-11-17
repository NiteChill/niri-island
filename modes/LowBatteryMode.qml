import QtQuick

import "../services"
import "../island"
import "../widgets"

// Island mode (an activity, put up by Activity): low battery warning, laid out like the iPhone's.
// As tall as the resting island: a power saver badge at the far left (one tap turns it on; yellow once
// it is), "Low Battery" in white, and at the far right what's left in red next to a red battery that
// slowly breathes. Clicking anywhere else opens the battery panel (and clears the warning).
IslandMode {
    id: mode

    readonly property var layout: Config.lowBattery
    readonly property bool saving: Sys.battery.profile === "powerSaver"
    readonly property real restHeight: island ? island.restHeight : 0

    implicitWidth: layout.width
    implicitHeight: restHeight

    // the battery breathes while the warning is up (only then: no cost the rest of the time)
    property real pulse: 1
    SequentialAnimation on pulse {
        running: mode.onScreen
        loops: Animation.Infinite
        onRunningChanged: {
            if (!running)
                mode.pulse = 1;
        }
        NumberAnimation {
            to: mode.layout.pulseMin
            duration: mode.layout.pulseDuration / 2
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 1
            duration: mode.layout.pulseDuration / 2
            easing.type: Easing.InOutSine
        }
    }

    // (not on the power saver badge: a parent TapHandler also fires for taps on its children)
    TapHandler {
        onTapped: (point, button) => {
            if (saver.contains(saver.mapFromItem(mode, point.position)))
                return;
            Activity.dismiss("lowBattery");
            mode.requestState("battery");
        }
    }

    // centred: the island is never narrower than island.minWidth
    Item {
        x: (mode.width - mode.implicitWidth) / 2
        width: mode.implicitWidth
        height: mode.implicitHeight

        // power saver: one tap; turns solid yellow once it's on
        Badge {
            id: saver
            x: Config.activity.inset
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - 2 * Config.activity.inset
            icon: mode.layout.saverIcon
            tint: mode.saving ? Config.colors.powerSaver : Config.colors.text
            solid: mode.saving
            clickable: true
            onClicked: Sys.setPowerProfile("powerSaver")
        }

        StyledText {
            anchors.left: saver.right
            anchors.leftMargin: Config.activity.spacing
            anchors.right: percent.left
            anchors.rightMargin: Config.activity.spacing
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            font.pixelSize: Config.activity.titleSize
            text: mode.layout.title
        }

        StyledText {
            id: percent
            anchors.right: battery.left
            anchors.rightMargin: mode.layout.iconGap
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Config.activity.titleSize
            font.features: {
                "tnum": 1
            }
            color: Config.colors.danger
            text: Sys.battery.percentage + "%"
        }

        // battery: dim outline, red fill clipped to the level
        Item {
            id: battery
            anchors.right: parent.right
            anchors.rightMargin: Config.activity.edge
            anchors.verticalCenter: parent.verticalCenter
            width: mode.layout.iconSize
            height: mode.layout.iconSize
            opacity: mode.pulse

            Icon {
                anchors.fill: parent
                name: mode.layout.icon
                color: Config.colors.danger
                opacity: Config.idle.overlayOpacity
            }
            Item {
                width: parent.width * Sys.battery.level
                height: parent.height
                clip: true
                Icon {
                    width: battery.width
                    height: battery.height
                    name: mode.layout.icon
                    color: Config.colors.danger
                }
            }
        }
    }
}
