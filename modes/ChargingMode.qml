import QtQuick

import "../services"
import "../island"
import "../widgets"

// Notch mode (an activity, put up by Activity): the charger was plugged in. One line (island.activityHeight):
// "Charging" at the left ("Fully charged" once UPower says so), and at the right the level in green next
// to the bar's battery (same widget, green while charging), whose fill sweeps up to the level as the alert
// appears; then the bolt pops in, cut into its end (charging.bolt, the bar.battery.badge look).
IslandMode {
    id: mode

    readonly property var layout: Config.charging
    readonly property real restHeight: island ? island.restHeight : 0
    readonly property bool full: Sys.battery.full || Sys.battery.percentage >= 100

    implicitWidth: layout.width
    implicitHeight: restHeight

    // empty from activation, fills to the level once on screen (appeared)
    property real fill: Sys.battery.level
    Behavior on fill {
        id: fillBehavior
        NumberAnimation {
            duration: mode.layout.fillDuration
            easing.type: Easing.OutCubic
        }
    }
    // the bolt: once the sweep has landed (not while "Fully charged")
    property bool swept: false
    Timer {
        id: sweepDone
        interval: mode.layout.fillDuration
        onTriggered: mode.swept = true
    }
    onActiveChanged: {
        if (!active)
            return;
        fillBehavior.enabled = false;
        fill = 0;
        fillBehavior.enabled = true;
        sweepDone.stop();
        swept = false;
    }
    onAppeared: {
        fill = Qt.binding(() => Sys.battery.level);
        sweepDone.restart();
    }

    TapHandler {
        onTapped: {
            Activity.dismiss("charging");
            mode.requestState("battery");
        }
    }

    // centred: the island is never narrower than island.minWidth
    Item {
        x: (mode.width - mode.implicitWidth) / 2
        width: mode.implicitWidth
        height: mode.implicitHeight

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: Config.activity.edge
            anchors.right: percent.left
            anchors.rightMargin: Config.activity.spacing
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            font.pixelSize: Config.activity.titleSize
            text: mode.full ? mode.layout.fullText : mode.layout.title
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
            color: Sys.battery.color
            text: Sys.battery.percentage + "%"
        }

        // the bar's battery, at the same size (as tall as a bar item's highlight). Its width keeps the bolt's
        // room from the start, so nothing moves when the bolt pops in.
        Item {
            id: battery
            readonly property var badge: Config.bar.battery.badge
            anchors.right: parent.right
            anchors.rightMargin: Config.activity.edge
            anchors.verticalCenter: parent.verticalCenter
            width: Config.bar.battery.size + (mode.layout.bolt ? boltCut.overhangX : 0)
            height: Config.bar.item.height
            CutoutBadge {
                id: boltCut
                height: parent.height
                shown: mode.layout.bolt && mode.swept && !mode.full
                centered: true
                icon: battery.badge.chargingIcon
                size: battery.badge.chargingSize
                overhangX: size / 2 + battery.badge.offset
                gap: battery.badge.gap
                contentWidth: Config.bar.battery.size
                contentHeight: alertBattery.drawnHeight
                Battery {
                    id: alertBattery
                    level: mode.fill
                }
            }
        }
    }
}
