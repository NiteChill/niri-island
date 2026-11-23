import QtQuick

import "../services"

// Bluetooth icon for the bar: bright while Bluetooth is on, dim (bar.overlayOpacity) while off.
Item {
    id: bt

    // config
    readonly property var icon: Config.bar.bluetooth

    // style
    width: icon.size
    height: parent.height
    anchors.verticalCenter: parent.verticalCenter

    // content
    Icon {
        name: bt.icon.icon
        color: palette.windowText
        opacity: Sys.bluetooth.enabled ? 1 : Config.bar.overlayOpacity

        width: bt.icon.size
        height: bt.icon.size
        anchors.centerIn: bt
    }
}
