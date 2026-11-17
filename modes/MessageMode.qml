import QtQuick

import "../services"
import "../island"
import "../widgets"

// Island mode (an activity, put up by Activity): a short message from a script
// (`qs ipc call osd message "text" "icon.svg"`). As tall as the resting island: the icon in a soft round
// badge at the far left (concentric with the island's end) and one line of text, as wide as the text
// needs (up to message.maxWidth).
IslandMode {
    id: mode

    readonly property var layout: Config.message
    readonly property real restHeight: island ? island.restHeight : 0
    // the message, kept while it fades out even if Activity has moved on
    property var info: ({
            "text": "",
            "icon": Config.message.icon
        })
    Connections {
        target: Activity
        function onCurrentChanged() {
            const c = Activity.current;
            if (c && c.kind === "message")
                mode.info = c.data;
        }
    }

    readonly property real badgeSize: restHeight - 2 * Config.activity.inset
    readonly property real chrome: Config.activity.inset + badgeSize + Config.activity.spacing + Config.activity.edge
    implicitWidth: Math.min(layout.maxWidth, chrome + label.implicitWidth)
    implicitHeight: restHeight

    Item {
        // centred: the island is never narrower than island.minWidth, which can be wider than the message
        x: (mode.width - mode.implicitWidth) / 2
        width: mode.implicitWidth
        height: mode.implicitHeight

        Badge {
            id: badge
            x: Config.activity.inset
            anchors.verticalCenter: parent.verticalCenter
            height: mode.badgeSize
            icon: mode.info.icon
            tint: Config.colors.accent
        }
        StyledText {
            id: label
            anchors.left: badge.right
            anchors.leftMargin: Config.activity.spacing
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, mode.layout.maxWidth - mode.chrome)
            elide: Text.ElideRight
            font.pixelSize: Config.activity.titleSize
            text: mode.info.text
        }
    }
}
