pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../island"
import "../widgets"

// Calendar dropdown (under the bar's clock): the month on top with ‹ › to move between months (a click on
// the month's name comes back to this one), the weekdays' letters, then the days, today in a filled
// circle (time.accent); days of the months around in grey; optionally the week numbers at the left
// (time.showWeekNumber). Left / Right or the wheel change the month. Data: Sys.calendarMonth (it only
// changes with the date).
IslandMode {
    id: mode

    readonly property var layout: Config.time
    launcher: Config.time.launcher

    // months from this one (0 = this month); back to 0 each time it opens
    property int offset: 0
    onActiveChanged: {
        if (active) {
            offset = 0;
            wheelSum = 0;
        }
    }
    readonly property var month: {
        Sys.today;
        return Sys.calendarMonth(offset);
    }
    readonly property var weekdays: Sys.weekdayNames(layout.weekLetterFormat).map(s => s.slice(0, layout.weekLetters))

    keyTarget: mode
    Keys.onLeftPressed: offset--
    Keys.onRightPressed: offset++
    // the wheel or two fingers move months: one month per wheel notch's worth (a touchpad sends many small
    // steps; one month each raced through the year)
    property real wheelSum: 0
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            mode.wheelSum += event.angleDelta.y;
            while (Math.abs(mode.wheelSum) >= 120) {
                const up = mode.wheelSum > 0;
                mode.offset += up ? -1 : 1;
                mode.wheelSum += up ? -120 : 120;
            }
        }
    }

    readonly property real contentWidth: Config.panel.width - 2 * Config.panel.padding
    readonly property real weekColumn: layout.showWeekNumber ? layout.weekColumn : 0
    readonly property real cell: (contentWidth - weekColumn) / 7
    readonly property real rowHeight: layout.dayCircle + layout.rowGap
    implicitWidth: Config.panel.width
    // always room for six weeks: the dropdown doesn't change height from month to month
    implicitHeight: 2 * Config.panel.padding + Config.panel.header.height + layout.weekdayHeight + 6 * rowHeight

    Item {
        x: Config.panel.padding
        y: Config.panel.padding
        width: mode.contentWidth
        height: mode.implicitHeight - 2 * Config.panel.padding

        PanelHeader {
            id: header
            title: mode.month.title
            Row {
                id: arrows
                spacing: mode.layout.arrowGap
                Repeater {
                    model: [-1, 1]
                    delegate: Rectangle {
                        id: arrow
                        required property int modelData
                        width: mode.layout.arrowSize
                        height: width
                        radius: Config.corner("pill", height)
                        color: Qt.alpha(palette.windowText, arrowHover.hovered ? Config.panel.list.selectedOpacity : 0)
                        Icon {
                            anchors.centerIn: parent
                            width: mode.layout.arrowIconSize
                            height: width
                            name: arrow.modelData < 0 ? mode.layout.previousIcon : mode.layout.nextIcon
                            color: palette.windowText
                        }
                        HoverHandler {
                            id: arrowHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: mode.offset += arrow.modelData
                        }
                    }
                }
            }
        }
        // a click on the month's name: back to this month. Only over the name: a handler on the whole
        // header also fired for taps on the arrows, so › went forward and straight back (it never left
        // the year)
        Item {
            width: header.width - arrows.width - 2 * Config.panel.list.rowPadding
            height: header.height
            TapHandler {
                enabled: mode.offset !== 0
                onTapped: mode.offset = 0
            }
        }

        // the weekdays' letters
        Row {
            id: letters
            anchors.top: header.bottom
            x: mode.weekColumn
            height: mode.layout.weekdayHeight
            Repeater {
                model: mode.weekdays
                delegate: StyledText {
                    required property string modelData
                    width: mode.cell
                    height: mode.layout.weekdayHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: mode.layout.weekLetterSize
                    color: palette.placeholderText
                    text: modelData
                }
            }
        }

        // the weeks
        Column {
            anchors.top: letters.bottom
            Repeater {
                model: mode.month.weeks
                delegate: Row {
                    id: week
                    required property var modelData
                    height: mode.rowHeight
                    StyledText {
                        visible: mode.layout.showWeekNumber
                        width: mode.weekColumn
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: mode.layout.weekLetterSize
                        color: palette.placeholderText
                        text: week.modelData.number
                    }
                    Repeater {
                        model: week.modelData.days
                        delegate: Item {
                            id: day
                            required property var modelData
                            width: mode.cell
                            height: mode.rowHeight
                            Rectangle {
                                visible: day.modelData.today
                                anchors.centerIn: parent
                                width: mode.layout.dayCircle
                                height: width
                                radius: width / 2
                                color: mode.layout.accent
                            }
                            StyledText {
                                anchors.centerIn: parent
                                font.pixelSize: mode.layout.dayNumberSize
                                font.features: {
                                    "tnum": 1
                                }
                                color: day.modelData.today ? Config.onColor(mode.layout.accent) : day.modelData.inMonth ? palette.windowText : palette.placeholderText
                                opacity: day.modelData.inMonth || day.modelData.today ? 1 : mode.layout.otherMonthOpacity
                                text: day.modelData.day
                            }
                        }
                    }
                }
            }
        }
    }
}
