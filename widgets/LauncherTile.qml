import QtQuick
import Quickshell

import "../services"

// One tile of the launcher's grid (modes/SearchMode.qml, nothing typed): a favorite or an app. Its icon
// (an app's own, else a glyph on a soft rounded tile, panels in the accent) over its name, grey unless
// it's the selected one; a command waiting for its second Enter says so in red (search.pins.*).
Item {
    id: tile

    // the launcher entry it shows: { kind, name, app } or { kind, name, icon, panel / action }
    property var entry: ({})
    property bool current: false
    property bool confirming: false

    readonly property var look: Config.search.pins

    width: 0
    height: look.tileHeight

    Item {
        id: tileIcon
        anchors.horizontalCenter: parent.horizontalCenter
        y: tile.look.padding
        width: tile.look.iconSize
        height: tile.look.iconSize
        readonly property color tint: tile.entry.panel ? Config.colors.accent : palette.windowText
        Rectangle {
            anchors.fill: parent
            visible: !tile.entry.app
            radius: Config.corner("tile", height)
            color: Qt.alpha(tileIcon.tint, Config.activity.badgeOpacity)
        }
        Image {
            anchors.fill: parent
            visible: !!tile.entry.app
            source: tile.entry.app ? Quickshell.iconPath(tile.entry.app.icon, "application-x-executable") : ""
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Icon {
            anchors.centerIn: parent
            visible: !tile.entry.app
            width: parent.width * Config.search.panelIconScale
            height: width
            name: tile.entry.icon || ""
            color: tileIcon.tint
        }
    }
    StyledText {
        anchors.top: tileIcon.bottom
        anchors.topMargin: tile.look.nameGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 2 * tile.look.padding
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: tile.look.nameSize
        color: tile.confirming ? Config.colors.danger : tile.current ? palette.windowText : palette.placeholderText
        text: tile.confirming ? Config.search.confirmText : tile.entry.name || ""
    }
}
