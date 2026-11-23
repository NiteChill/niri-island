import QtQuick

import "../services"

// Every dropdown, by name (the name Activity.open takes). Put once inside the dropdown surface's Island
// (surfaces/Dropdown.qml): a new dropdown is registered here only, and opened from a bar item, the
// launcher or `qs ipc call island toggle <name>`. Those opened from the bar drop under their icon
// (Bar.anchorFor); the others under the notch (none today).
Item {
    anchors.fill: parent
    readonly property bool isModeList: true

    WifiMode {
        name: "wifi"
    }
    BluetoothMode {
        name: "bluetooth"
    }
    BatteryMode {
        name: "battery"
    }
    CalendarMode {
        name: "calendar"
    }
    QuickSettingsMode {
        name: "quickSettings"
    }
    // the bar's app name: what to do with the focused window
    MenuMode {
        name: "app"
        title: Sys.focusedApp
        subtitle: Sys.focusedTitle !== Sys.focusedApp ? Sys.focusedTitle : ""
        items: Config.bar.appMenu.items
    }
    // a tray icon's menu (the app's own, drawn here)
    TrayMenuMode {
        name: "tray"
    }
    // the bar's logo: places, the launcher, the session
    MenuMode {
        name: "system"
        items: Config.bar.logo.items
    }
}
