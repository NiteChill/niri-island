import QtQuick

import "../services"

// A dropdown's header: its title at the left (panel.header.*), something at the right (a Switch, a value),
// passed as children.
Item {
    id: header

    property string title
    default property alias trailing: right.data

    width: parent ? parent.width : 0
    height: Config.panel.header.height

    StyledText {
        anchors.left: parent.left
        anchors.leftMargin: Config.panel.list.rowPadding
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: Config.panel.header.titleSize
        font.weight: Config.panel.header.titleWeight
        text: header.title
    }
    Item {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: Config.panel.list.rowPadding
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
