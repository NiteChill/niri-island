import QtQuick

import "../services"

// Wi-Fi icon: dim full icon (all three bars, idle.overlayOpacity) with the actual number of bars on top.
// Defaults to the current connection (idle island); the Wi-Fi panel sets `level`, `size` and `tint` for
// each network in its list.
// Always drawn; in the idle island the IconSlot around it shows/hides it (Sys.wifi.connected).
Item {
    id: wifi

    // config
    readonly property var icon: Config.idle.wifi

    // 0 = no signal, 1 to 3 = number of bars
    property int level: Sys.wifi.bars
    property real size: icon.size
    property color tint: Config.colors.text
    readonly property string levelName: level > 0 ? icon.icons[Math.min(level, icon.icons.length) - 1] : ""

    // style
    width: size
    height: parent ? parent.height : size
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    // content
    Icon {
        name: wifi.icon.icons[wifi.icon.icons.length - 1]
        color: wifi.tint
        opacity: Config.idle.overlayOpacity

        width: wifi.size
        height: wifi.size
        anchors.centerIn: wifi
    }

    Icon {
        visible: wifi.level > 0
        name: wifi.levelName
        color: wifi.tint

        width: wifi.size
        height: wifi.size
        anchors.centerIn: wifi
    }
}
