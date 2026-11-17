import QtQuick

import "../services"

// Bluetooth icon for the idle island (a device other than headphones is connected). Always drawn; the
// IconSlot around it shows/hides it.
Item {
    id: bt

    // config
    readonly property var icon: Config.idle.bluetooth

    // style
    width: icon.size
    height: parent.height
    anchors.verticalCenter: parent.verticalCenter

    // content
    Icon {
        name: bt.icon.icon
        color: Config.colors.text

        width: bt.icon.size
        height: bt.icon.size
        anchors.centerIn: bt
    }
}
