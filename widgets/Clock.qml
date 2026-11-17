import QtQuick

import "../services"

// Date and time for the idle island, from Sys.time. Formats come from config (idle.clock: a 24 h and a
// 12 h time format, picked by Sys.hour24); an empty format hides that part (by default only the time shows).
Row {
    id: clock
    spacing: Config.idle.clock.spacing
    anchors.verticalCenter: parent.verticalCenter
    // same-width digits, so the island doesn't resize slightly every minute
    readonly property var features: Config.idle.clock.tabularDigits ? { "tnum": 1 } : {}

    StyledText {
        visible: Config.idle.clock.dateFormat !== ""
        text: Qt.formatDateTime(Sys.time, Config.idle.clock.dateFormat)
        font.features: clock.features
    }
    StyledText {
        readonly property string format: Sys.hour24 ? Config.idle.clock.timeFormat : Config.idle.clock.timeFormat12h
        visible: format !== ""
        text: Qt.formatDateTime(Sys.time, format)
        font.features: clock.features
    }
}
