pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// Time panel (click the clock in the idle island), in the battery panel's language:
//  - on top, centred: the time big, hours and minutes as odometer wheels (RollingNumber) that roll on each
//    new minute, the seconds small and grey after them; under it the month and year in grey (the week
//    row shows the weekday and the day; + the week number, time.showWeekNumber)
//  - the day on an ArcGauge (the battery panel's bar): midnight to midnight, filled in orange up to now,
//    a tick per hour, every 6 hours brighter. Opening sweeps it up from midnight
//  - the current week like the Calendar widget: weekday letters in grey, today in a solid orange circle,
//    weekends grey
// Seconds only tick (Sys.timeSeconds) while this panel is open; the rest of the time the clock is per
// minute. The bar moves per minute too (a second is invisible on it).
IslandMode {
    id: mode

    readonly property var layout: Config.time
    launcher: Config.time.launcher
    keyTarget: mode

    // seconds only while open
    Binding {
        target: Sys
        property: "timeSeconds"
        value: mode.active
    }

    // the time shown: frozen while the panel animates out (the per-second clock switches off then, and
    // the seconds jumped to :00 mid-fade)
    property date now: Sys.time
    onActiveChanged: {
        if (active)
            now = Qt.binding(() => Sys.time);
        else
            now = now;
    }
    readonly property int hours: now.getHours()
    readonly property int minutes: now.getMinutes()
    readonly property int shownHours: Sys.hour24 ? hours : (hours % 12 || 12)
    // how much of the day has gone, per minute
    readonly property real dayLevel: (hours * 60 + minutes) / 1440

    // ---- the wheels: roll on a normal +1, jump on anything else (59 -> 00, 23 -> 0, opening after a
    // while, a suspend), or they'd spin backwards through every digit ----
    property real hourWheel: shownHours
    property real minuteWheel: minutes
    Behavior on hourWheel {
        id: hourRoll
        NumberAnimation {
            duration: Config.panel.number.rollDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on minuteWheel {
        id: minuteRoll
        NumberAnimation {
            duration: Config.panel.number.rollDuration
            easing.type: Easing.OutCubic
        }
    }
    onShownHoursChanged: {
        hourRoll.enabled = active && shownHours === Math.round(hourWheel) + 1;
        hourWheel = shownHours;
        hourRoll.enabled = true;
    }
    onMinutesChanged: {
        minuteRoll.enabled = active && minutes === Math.round(minuteWheel) + 1;
        minuteWheel = minutes;
        minuteRoll.enabled = true;
    }

    // the seconds only once the per-second clock has ticked: while closed the clock is per minute, so right
    // after opening it still reads :00 for up to a second (it showed during the opening animation)
    property bool secondsReady: false
    onOnScreenChanged: if (!onScreen)
        secondsReady = false
    onNowChanged: if (active && Sys.timeSeconds)
        secondsReady = true
    readonly property string secondsText: Qt.formatDateTime(now, layout.secondsFormat) + (Sys.hour24 ? "" : " " + Qt.formatDateTime(now, layout.amPmFormat))
    readonly property string dateText: Qt.formatDateTime(now, layout.dateFormat) + (layout.showWeekNumber ? layout.weekNumberFormat.arg(Sys.weekNumber) : "")

    implicitWidth: Config.panel.width
    implicitHeight: 2 * Config.panel.padding + clock.height + Config.panel.caption.gap + dateLabel.height + Config.panel.arc.gapAbove + dayGauge.implicitHeight + Config.panel.arc.gapBelow + layout.weekHeight

    Item {
        id: content
        x: Config.panel.padding
        y: Config.panel.padding
        width: mode.implicitWidth - 2 * Config.panel.padding
        height: mode.implicitHeight - 2 * Config.panel.padding

        // ---- the time ----
        Row {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            height: hoursWheel.height

            RollingNumber {
                id: hoursWheel
                value: mode.hourWheel
                minDigits: Sys.hour24 ? 2 : 1
                pixelSize: Config.panel.number.size
                weight: Config.panel.number.weight
                fade: Config.panel.number.rollFade
                travel: Config.panel.number.rollTravel
            }
            StyledText {
                anchors.baseline: hoursWheel.baseline
                font.pixelSize: Config.panel.number.size
                font.weight: Config.panel.number.weight
                text: ":"
            }
            RollingNumber {
                value: mode.minuteWheel
                minDigits: 2
                pixelSize: Config.panel.number.size
                weight: Config.panel.number.weight
                fade: Config.panel.number.rollFade
                travel: Config.panel.number.rollTravel
            }
            Item {
                width: mode.layout.secondsGap
                height: 1
            }
            StyledText {
                anchors.baseline: hoursWheel.baseline
                font.pixelSize: Config.panel.number.smallSize
                font.weight: Config.panel.number.weight
                font.features: {
                    "tnum": 1
                }
                color: Config.colors.secondary
                text: mode.secondsText
                opacity: mode.secondsReady ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Config.motion.hoverFade
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // ---- the date ----
        StyledText {
            id: dateLabel
            anchors.top: clock.bottom
            anchors.topMargin: Config.panel.caption.gap
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: Config.panel.caption.size
            color: Config.colors.secondary
            text: mode.dateText
        }

        // ---- the day ----
        ArcGauge {
            id: dayGauge
            anchors.top: dateLabel.bottom
            anchors.topMargin: Config.panel.arc.gapAbove
            width: parent.width
            value: mode.dayLevel
            tint: mode.layout.accent
            active: mode.active
            ticks: mode.layout.ticks.count
            majorEvery: mode.layout.ticks.majorEvery
        }

        // ---- the week ----
        Row {
            id: week
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: dayGauge.bottom
            anchors.topMargin: Config.panel.arc.gapBelow
            height: mode.layout.weekHeight
            readonly property real cell: width / 7

            Repeater {
                model: Sys.week
                delegate: Item {
                    id: weekDay
                    required property var modelData
                    readonly property bool weekend: mode.layout.weekendDays.includes(modelData.weekday)
                    width: week.cell
                    height: week.height

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pixelSize: mode.layout.weekLetterSize
                        color: Config.colors.secondary
                        text: Qt.formatDate(weekDay.modelData.date, mode.layout.weekLetterFormat).slice(0, mode.layout.weekLetters)
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: mode.layout.dayCircle
                        height: width
                        radius: width / 2
                        color: weekDay.modelData.today ? mode.layout.accent : "transparent"
                        StyledText {
                            anchors.centerIn: parent
                            font.pixelSize: mode.layout.dayNumberSize
                            font.features: {
                                "tnum": 1
                            }
                            color: weekDay.modelData.today ? Config.island.color : weekDay.weekend ? Config.colors.secondary : Config.colors.text
                            text: weekDay.modelData.day
                        }
                    }
                }
            }
        }
    }
}
