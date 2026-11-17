import QtQuick

import "../services"
import "../island"
import "../widgets"

// Island mode (an activity, put up by Activity): headphones connected, like the iPhone's "Connected
// accessory": a big headphones glyph at the far left that bounces in, then a grey "Connected" above the
// device name. As wide as the name needs (between headphones.minWidth and maxWidth).
// Clicking it shows the volume.
IslandMode {
    id: mode

    readonly property var layout: Config.headphones
    // the device, kept while it fades out even if Activity has moved on
    property string device: ""
    Connections {
        target: Activity
        function onCurrentChanged() {
            const c = Activity.current;
            if (c && c.kind === "headphones")
                mode.device = c.data.name;
        }
    }

    readonly property real chrome: Config.activity.edge + layout.iconSize + Config.activity.spacing + Config.activity.edge
    implicitWidth: Math.max(layout.minWidth, Math.min(layout.maxWidth, chrome + lines.naturalWidth))
    implicitHeight: Config.activity.tallHeight

    // the glyph bounces in: small from activation, springs out once on screen (appeared)
    property real iconPop: 1
    Behavior on iconPop {
        id: popBehavior
        SpringAnimation {
            spring: Config.spring(mode.layout.iconPop).spring
            damping: Config.spring(mode.layout.iconPop).damping
            epsilon: 0.001
        }
    }
    onActiveChanged: {
        if (active) {
            popBehavior.enabled = false;
            iconPop = layout.iconPopFrom;
            popBehavior.enabled = true;
        }
    }
    onAppeared: iconPop = 1

    TapHandler {
        onTapped: Activity.feedback("volume")
    }

    Item {
        x: (mode.width - mode.implicitWidth) / 2
        width: mode.implicitWidth
        height: mode.implicitHeight

        Icon {
            id: icon
            x: Config.activity.edge
            anchors.verticalCenter: parent.verticalCenter
            width: mode.layout.iconSize
            height: mode.layout.iconSize
            scale: mode.iconPop
            name: mode.layout.icon
            color: Config.colors.text
        }
        TitleStack {
            id: lines
            anchors.left: icon.right
            anchors.leftMargin: Config.activity.spacing
            anchors.right: parent.right
            anchors.rightMargin: Config.activity.edge
            anchors.verticalCenter: parent.verticalCenter
            caption: mode.layout.text
            title: mode.device
        }
    }
}
