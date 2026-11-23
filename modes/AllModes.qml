import QtQuick

// Every mode of the notch, by name (the name is the Activity kind). Put once inside the notch's Island in
// shell.qml: a new notch mode is registered here only. (The dropdowns are in AllDropdowns.qml.)
// Island finds the modes inside it (Island.modeList); this item just fills it.
Item {
    anchors.fill: parent
    readonly property bool isModeList: true

    // at rest: the small empty notch
    RestMode {
        name: "rest"
    }
    // something dragged over the notch: a small drop zone
    DropMode {
        name: "drop"
    }
    // grown out of the notch (a click on it, IPC): the player and the shelf, a navbar between them
    MediaMode {
        name: "media"
    }
    ShelfMode {
        name: "shelf"
    }
    // the wallpaper picker (the logo's menu, the launcher): the shelf's carousel, for the desktop's picture
    WallpaperMode {
        name: "wallpaper"
    }
    // the launcher (Mod+Space, the logo's menu): the notch grows into a search field, the results unfolding
    // below it
    SearchMode {
        name: "search"
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
