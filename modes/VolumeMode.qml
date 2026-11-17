import QtQuick

import "../services"
import "../island"
import "../widgets"

// Island mode (an activity, put up by Activity): output volume. A LevelRow: the speaker (dimmed full speaker
// with the waves for the level bright on top, like the Wi-Fi icon; crossed out when muted; click mutes), a
// level bar you can drag or scroll (past 100 % in red, bumps at the ends), and the percentage. As tall
// as the resting island, so the island only widens. Not shown while quick settings is (it has the same row).
IslandMode {
    id: mode

    readonly property var layout: Config.volume

    implicitWidth: layout.width
    implicitHeight: island ? island.restHeight : 0

    LevelRow {
        x: Config.activity.edge
        width: mode.implicitWidth - 2 * Config.activity.edge
        anchors.verticalCenter: parent.verticalCenter
        kind: "volume"
        live: mode.hasAppeared
        starting: mode.active && !mode.hasAppeared
        iconSize: mode.layout.iconSize
        showValue: mode.layout.showPercent
        valueSize: mode.layout.percentSize
    }
}
