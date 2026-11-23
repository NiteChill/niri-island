pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// Island mode (an activity, put up by Activity): joined a Wi-Fi network. Same family as the headphones
// alert ("Connected accessory"): a big blue Wi-Fi fan at the far left whose bars light up one after the
// other up to the signal strength, like it's finding the signal, then a grey "Connected" above the
// network name. As wide as the name needs (between wifiConnected.minWidth and maxWidth).
IslandMode {
    id: mode

    readonly property var layout: Config.wifiConnected
    // the network, kept while it fades out even if Activity has moved on
    property string ssid: ""
    Connections {
        target: Activity
        function onCurrentChanged() {
            const c = Activity.current;
            if (c && c.kind === "wifiConnected")
                mode.ssid = c.data.ssid;
        }
    }

    // 1 to 3 bars, from the live signal
    readonly property int bars: Math.max(1, Sys.wifi.bars)
    // bars lit so far: none from activation, counts up once on screen (appeared)
    property int lit: 0
    onActiveChanged: {
        if (active) {
            lit = 0;
            barTimer.stop();
        }
    }
    onAppeared: barTimer.restart()
    Timer {
        id: barTimer
        interval: mode.layout.barDelay
        repeat: true
        onTriggered: {
            mode.lit++;
            if (mode.lit >= mode.bars)
                stop();
        }
    }

    readonly property real chrome: Config.activity.edge + layout.iconSize + Config.activity.spacing + Config.activity.edge
    implicitWidth: Math.max(layout.minWidth, Math.min(layout.maxWidth, chrome + lines.naturalWidth))
    implicitHeight: Config.activity.tallHeight

    Item {
        x: (mode.width - mode.implicitWidth) / 2
        width: mode.implicitWidth
        height: mode.implicitHeight

        // the fan: dim full icon, the lit bars on top (each its own icon, faded in as it lights)
        Item {
            id: fan
            x: Config.activity.edge
            anchors.verticalCenter: parent.verticalCenter
            width: mode.layout.iconSize
            height: mode.layout.iconSize

            Icon {
                anchors.fill: parent
                name: Config.bar.wifi.icons[Config.bar.wifi.icons.length - 1]
                color: Config.colors.accent
                opacity: Config.bar.overlayOpacity
            }
            Repeater {
                model: Config.bar.wifi.icons.length
                delegate: Icon {
                    required property int index
                    anchors.fill: parent
                    name: Config.bar.wifi.icons[index]
                    color: Config.colors.accent
                    // only the highest lit bar's icon shows (each icon already contains the bars below it)
                    opacity: index === Math.min(mode.lit, mode.bars) - 1 ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: mode.layout.barFade
                        }
                    }
                }
            }
        }

        TitleStack {
            id: lines
            anchors.left: fan.right
            anchors.leftMargin: Config.activity.spacing
            anchors.right: parent.right
            anchors.rightMargin: Config.activity.edge
            anchors.verticalCenter: parent.verticalCenter
            caption: mode.layout.text
            title: mode.ssid
        }
    }
}
