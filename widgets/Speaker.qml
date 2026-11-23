import QtQuick

import "../services"

// Speaker icon, like the Wi-Fi icon: the full speaker (every wave) dimmed (idle.overlayOpacity) with the waves
// for the real level bright on top (volume.icons share one drawing, so they line up); muted = the
// crossed-out speaker alone. Used by the volume pop-up and quick settings. Size it from outside.
Item {
    id: speaker

    property real level: Sys.audio.volume
    property bool muted: Sys.audio.muted
    property color tint: palette.windowText

    readonly property var vol: Config.volume

    Icon {
        anchors.fill: parent
        visible: !speaker.muted
        name: speaker.vol.icons[speaker.vol.icons.length - 1]
        color: speaker.tint
        opacity: Config.bar.overlayOpacity
    }
    Icon {
        anchors.fill: parent
        name: speaker.muted ? speaker.vol.mutedIcon : speaker.level <= 0 ? speaker.vol.icons[0] : speaker.level < speaker.vol.lowLevel ? speaker.vol.icons[1] : speaker.vol.icons[2]
        color: speaker.tint
    }
}
