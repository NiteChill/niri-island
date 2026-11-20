import QtQuick

// Every island mode, by name (the name is the Activity kind). Put once inside the Island in shell.qml:
// a new mode is registered here only.
// Island finds the modes inside it (Island.modeList); this item just fills the island.
Item {
    anchors.fill: parent

    // the modes the user opens (the rest are activities Activity puts up)
    readonly property var panels: ["idle", "battery", "wifi", "bluetooth", "search", "time", "quickSettings", "media", "wallpaper", "screenshots"]

    // panels (opened by the user)
    IdleMode {
        name: "idle"
    }
    BatteryMode {
        name: "battery"
    }
    WifiMode {
        name: "wifi"
    }
    BluetoothMode {
        name: "bluetooth"
    }
    SearchMode {
        name: "search"
    }
    TimeMode {
        name: "time"
    }
    QuickSettingsMode {
        name: "quickSettings"
    }
    MediaMode {
        name: "media"
    }
    WallpaperMode {
        name: "wallpaper"
    }
    ScreenshotsMode {
        name: "screenshots"
    }
    // calm mode's empty pill (shell.qml shows it instead of idle while Activity.calm)
    CalmMode {
        name: "calm"
    }
    // activities (Activity puts them up)
    VolumeMode {
        name: "volume"
    }
    BrightnessMode {
        name: "brightness"
    }
    MicrophoneMode {
        name: "microphone"
    }
    MessageMode {
        name: "message"
    }
    NotificationMode {
        name: "notification"
    }
    ScreenshotMode {
        name: "screenshot"
    }
    LowBatteryMode {
        name: "lowBattery"
    }
    ChargingMode {
        name: "charging"
    }
    WifiConnectedMode {
        name: "wifiConnected"
    }
    HeadphonesMode {
        name: "headphones"
    }
    NowPlayingMode {
        name: "nowPlaying"
    }
    GoodbyeMode {
        name: "goodbye"
    }
}
