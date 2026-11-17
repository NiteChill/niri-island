pragma ComponentBehavior: Bound

import QtQuick

import "../services"

// A whole number 0-999 shown as odometer wheels: give it a continuous `value` (animate it) and each digit
// rolls through the numbers in between, a digit turning only while the one to its right passes 9 -> 0,
// like a mechanical counter. A turning digit slides up or down (`travel` x its height) and fades out on
// the way (no clipping: no hard edge cutting it). Leading digits open their column only as the value
// reaches them (9 -> 10, 99 -> 100), fading in as it widens, so the width grows smoothly instead of
// jumping. At an integer value every digit sits still and sharp.
Item {
    id: number

    // 0 - 999; integers read sharp, anything in between is mid-roll
    property real value: 0
    property real pixelSize: Config.font.size
    property int weight: Config.font.weight
    property color color: Config.font.color
    // how fast a turning digit fades: 1 = as fast as it moves, higher = gone sooner
    property real fade: 1
    // how far a turning digit slides, in line heights
    property real travel: 1
    // digits always shown, with leading zeros (2: "07")
    property int minDigits: 1

    readonly property real v: Math.max(0, Math.min(999, value))

    implicitWidth: row.width
    implicitHeight: lines.height
    // the digits' baseline: a unit next to the number can use anchors.baseline
    baselineOffset: lines.ascent

    FontMetrics {
        id: lines
        font: metrics.font
    }

    TextMetrics {
        id: metrics
        font.family: Config.font.family
        font.variableAxes: ({
                "ROND": Config.font.roundness
            })
        font.pixelSize: number.pixelSize
        font.weight: number.weight
        // tabular digits share one width
        text: "0"
    }
    readonly property real digitWidth: metrics.advanceWidth

    // position of the wheel for 10^place, 0 to 10 (10 = back to 0): its digit, plus the turn it makes while
    // every digit to its right rolls from 9 to the next 0
    function wheel(place) {
        const unit = Math.pow(10, place);
        const below = v % unit; // what the wheels to the right show
        const carry = place === 0 ? 0 : Math.max(0, below - (unit - 1));
        return Math.floor(v / unit) % 10 + (place === 0 ? v % 1 : carry);
    }
    // how open a leading wheel's column is: 0 below 10^place - 1, 1 from 10^place (always 1 within minDigits)
    function opening(place) {
        return place < minDigits ? 1 : Math.max(0, Math.min(1, v - (Math.pow(10, place) - 1)));
    }

    Row {
        id: row
        Repeater {
            // hundreds, tens, ones
            model: [2, 1, 0]
            delegate: Item {
                id: column
                required property int modelData
                readonly property real pos: number.wheel(modelData)
                width: number.digitWidth * number.opening(modelData)
                height: lines.height
                visible: width > 0

                Repeater {
                    // 0-9 and a second 0 for the turn from 9
                    model: 11
                    delegate: StyledText {
                        required property int index
                        readonly property real offset: index - column.pos
                        visible: Math.abs(offset) < 1
                        x: column.width - number.digitWidth
                        y: offset * lines.height * number.travel
                        width: number.digitWidth
                        horizontalAlignment: Text.AlignHCenter
                        // fades faster than it moves, so two digits never read at once
                        opacity: Math.pow(1 - Math.abs(offset), number.fade) * number.opening(column.modelData)
                        color: number.color
                        font.pixelSize: number.pixelSize
                        font.weight: number.weight
                        font.features: {
                            "tnum": 1
                        }
                        text: String(index % 10)
                    }
                }
            }
        }
    }
}
