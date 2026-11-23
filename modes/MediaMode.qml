import QtQuick
import QtQuick.Window

import "../services"
import "../island"
import "../widgets"

// Media panel, Apple's Dynamic Island "now playing" expanded:
//  - top row: the cover (rounded tile; a music note without one), the title in white over the artist in
//    grey, and in the top-right corner the bars (MediaBars) dancing in the cover's color while it plays
//  - the progress: elapsed at the left, the bar (LevelSlider: drag to seek), the time left at the right;
//    always there (the panel never changes height): without the track's timing, an empty bar and --:--
//  - the controls, centred: previous, play / pause (bigger; the two glyphs swap with a quick scale), next
// Keys: Space plays / pauses, Left / Right go to the previous / next track, Escape closes.
// Data and actions: Sys.media*; the position from Sys's anchor (mediaPositionNow / mediaRate), animated.
// Ways in: the idle bars (idle.media), the launcher, `qs ipc call island toggle media`. Settings: media.*,
// media.padding (its own: more air than panel.padding), panel.width.
IslandMode {
    id: mode

    readonly property var layout: Config.media
    launcher: Config.media.launcher
    keyTarget: mode
    Keys.onSpacePressed: Sys.mediaPlayPause()
    Keys.onTabPressed: Activity.switchNotchTab()
    Keys.onLeftPressed: previousControl.skip()
    Keys.onRightPressed: nextControl.skip()

    // the track shown: frozen while the panel animates out
    property var media: Sys.media
    readonly property real contentWidth: Config.panel.width - 2 * layout.padding
    readonly property real progressHeight: Math.max(Config.slider.height, elapsed.implicitHeight)

    implicitWidth: Config.panel.width
    implicitHeight: normalHeight
    // from the content's sizes (not a positioner: see CLAUDE.md)
    // Timed = the player gives the track's length (and so a real position). Firefox / Zen build both from
    // the timing the web page hands them (navigator.mediaSession.setPositionState); a page that hasn't
    // (YouTube Music often, YouTube until a seek, live streams) gives no length and a position of 0. The
    // row stays where it is either way (the panel never changes height, like the iPhone's and Plasma's
    // players): untimed, an empty bar that can't be dragged and media.progress.unknownTime for both times.
    readonly property bool hasTimeline: media.length > 0
    readonly property real normalHeight: 2 * layout.padding + layout.art.size + layout.progress.gapAbove + progressHeight + layout.controls.gapAbove + layout.controls.playSize

    // ---- the shown position: read from Sys's anchor (mediaPositionNow) whenever the bar's fill has moved
    // one more step (media.progress.stepPixels; or the times a second), never per frame ----
    // A 60 fps animation to the track's end looked the same but kept the window redrawing all the time
    // (measured 2026-11-15: 121 CPU ticks per 9 s; the fill only moves a pixel every ~0.7 s on a 3-minute
    // song). Restarted whenever Sys's anchor moves (a seek, play / pause, a new track, a new length). Only
    // while open.
    property real position: 0
    readonly property int second: Math.floor(position)  // the times change once a second
    readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
    // how long the fill takes to move one step (media.progress.stepPixels device pixels: half a pixel reads
    // smoother, the fill's edge is antialiased) at the player's speed
    readonly property real pixelTime: layout.progress.stepPixels * 1000 * media.length / Math.max(1, bar.width * dpr * Math.max(Sys.mediaRate, 0.01))
    // the next read: the next pixel or the next whole second (the times), whichever comes first, at least
    // media.progress.minInterval away (short tracks)
    Timer {
        id: tick
        onTriggered: {
            mode.position = Sys.mediaPositionNow();
            mode.scheduleTick();
        }
    }
    function scheduleTick() {
        const rate = Sys.mediaRate;
        if (!active || rate <= 0 || media.length <= position)
            return;
        const toSecond = (Math.floor(position) + 1 - position) / rate * 1000;
        tick.interval = Math.max(layout.progress.minInterval, Math.min(pixelTime, toSecond));
        tick.restart();
    }
    function follow() {
        tick.stop();
        // not open (or animating out): the position stays where it is
        if (!active)
            return;
        position = Sys.mediaPositionNow();
        scheduleTick();
    }
    Connections {
        target: Sys
        function onMediaTimelineChanged() {
            if (!mode.dragging)
                mode.follow();
        }
    }
    // opened: the row just takes its state. Leaving: everything stays as it is (the track frozen, the
    // position stops where it is), reset once gone.
    onActiveChanged: {
        if (active)
            media = Qt.binding(() => Sys.media);
        else
            media = media;
        follow();
    }
    readonly property real trackLength: media.length
    onTrackLengthChanged: if (!dragging)
        follow()

    // dragging the bar moves the shown time only; the player is asked once, on release (like the
    // iPhone). The wheel has no release: its seek waits for a short pause (seekDelay).
    property bool dragging: bar.pressed || seekDelay.running
    function preview(seconds) {
        tick.stop();
        position = seconds;
    }
    function seekNow() {
        seekDelay.stop();
        Sys.mediaSeek(position);
    }
    Timer {
        id: seekDelay
        interval: mode.layout.progress.seekDelay
        onTriggered: mode.seekNow()
    }

    // 1:05, 12:40, 1:02:03
    function clock(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, r = s % 60;
        const two = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + two(m) + ":" + two(r) : m + ":" + two(r);
    }

    // previous / next: two white triangles (media.icons.skip, one triangle, drawn twice media.controls.skipStep
    // apart); sinks while pressed, dimmed when the player can't do it. Skipping (a click or the arrow key)
    // plays a little push: a new triangle grows in at the back, the first one slides into the second's
    // place, and the front one is pushed out, shrinking (media.controls.skipDuration). `back`: mirrored,
    // for previous. (An inline component: it can't see this file's ids, so everything comes in.)
    component SkipControl: Item {
        id: control
        property bool back: false
        property real size
        property bool available: true
        signal clicked
        function skip() {
            if (!available)
                return;
            push.restart();
            clicked();
        }
        // 0 -> 1 through one push; 1 = at rest (the new triangle in, the pushed one gone)
        property real p: 1
        NumberAnimation {
            id: push
            target: control
            property: "p"
            from: 0
            to: 1
            duration: Config.media.controls.skipDuration
            easing.type: Easing.OutCubic
        }
        width: size
        height: size
        opacity: available ? 1 : Config.media.controls.unavailableOpacity
        scale: tap.pressed ? Config.motion.pressScale : 1
        Behavior on scale {
            NumberAnimation {
                duration: Config.motion.pressDuration
                easing.type: Easing.OutCubic
            }
        }
        // the triangle's own centre in the icon box (from the glyph's outline), for growing / shrinking in place
        readonly property var part: {
            const g = Config.glyph(Config.media.icons.skip);
            const pr = g && g.parts && g.parts.length > 0 ? g.parts[0] : null;
            return pr ? { "cx": (pr.x + pr.w / 2 - g.x) / g.w, "cy": (pr.y + pr.h / 2 - g.y) / g.h } : { "cx": 0.5, "cy": 0.5 };
        }
        readonly property real step: size * Config.media.controls.skipStep
        Item {
            anchors.fill: parent
            transform: Scale {
                origin.x: control.size / 2
                xScale: control.back ? -1 : 1
            }
            Repeater {
                // 0: grows in at the back, 1: slides one place forward, 2: pushed out the front
                model: 3
                Icon {
                    id: tri
                    required property int index
                    readonly property real grow: index === 0 ? control.p : index === 1 ? 1 : 1 - control.p
                    x: control.step * (index === 0 ? 0 : index === 1 ? control.p : 1 + control.p)
                    width: control.size
                    height: control.size
                    name: Config.media.icons.skip
                    color: palette.windowText
                    opacity: tri.grow
                    visible: tri.grow > 0
                    transform: Scale {
                        origin.x: control.part.cx * control.size
                        origin.y: control.part.cy * control.size
                        xScale: tri.grow
                        yScale: tri.grow
                    }
                }
            }
        }
        HoverHandler {
            enabled: control.available
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: tap
            enabled: control.available
            onTapped: control.skip()
        }
    }


    // the panel's content, the panel's size, centred in the island (the mode is centred in it)
    Item {
        id: stage
        width: Config.panel.width
        height: mode.normalHeight
        x: (mode.width - width) / 2

        // ---- top row: cover, title / artist, bars ----
        Item {
            id: topRow
            x: mode.layout.padding
            y: mode.layout.padding
            width: mode.contentWidth
            height: mode.layout.art.size

            MediaCover {
                id: art
                width: mode.layout.art.size
                height: mode.layout.art.size
                iconSize: mode.layout.art.iconSize
            }

            MediaBars {
                id: bars
                // in the top-right corner, pushed in from the padding on both sides (cornerInset): small bars
                // tight in the corner looked cramped
                anchors.right: parent.right
                anchors.rightMargin: mode.layout.bars.cornerInset
                y: mode.layout.bars.cornerInset
                running: mode.onScreen && mode.media.playing
            }

            Item {
                id: titles
                anchors.left: parent.left
                anchors.leftMargin: mode.layout.art.size + mode.layout.textGap
                anchors.right: bars.left
                anchors.rightMargin: mode.layout.textGap
                anchors.verticalCenter: parent.verticalCenter
                // from the text, not artist.visible (see CLAUDE.md: `visible` is the effective visibility)
                height: title.implicitHeight + (artist.text !== "" ? mode.layout.lineGap + artist.implicitHeight : 0)
                StyledText {
                    id: title
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: mode.layout.titleSize
                    font.weight: mode.layout.titleWeight
                    color: mode.media.active ? palette.windowText : palette.placeholderText
                    text: mode.media.active ? mode.media.title || "" : mode.layout.nothingText
                }
                StyledText {
                    id: artist
                    visible: text !== ""
                    anchors.top: title.bottom
                    anchors.topMargin: mode.layout.lineGap
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: mode.layout.artistSize
                    color: palette.placeholderText
                    text: mode.media.active ? (mode.media.artist || mode.media.app || "") : ""
                }
            }
        }

        // the controls' and the progress bar's centres (the controls ride the panel's bottom edge)
        readonly property real controlsCentre: mode.normalHeight - mode.layout.padding - mode.layout.controls.playSize / 2
        readonly property real progressCentre: mode.layout.padding + mode.layout.art.size + mode.layout.progress.gapAbove + mode.progressHeight / 2

        // ---- progress: elapsed, bar, time left ----
        Item {
            id: progress
            width: mode.contentWidth
            height: mode.progressHeight
            x: (stage.width - width) / 2
            y: stage.progressCentre - height / 2

            TextMetrics {
                id: widest
                font: elapsed.font
                text: "-" + mode.clock(Math.max(mode.trackLength, 600)).replace(/[0-9]/g, "0")
            }
            StyledText {
                id: elapsed
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: widest.advanceWidth
                font.pixelSize: mode.layout.progress.timeSize
                font.features: {
                    "tnum": 1
                }
                color: palette.placeholderText
                text: mode.hasTimeline ? mode.clock(mode.second) : mode.layout.progress.unknownTime
            }
            LevelSlider {
                id: bar
                anchors.left: elapsed.right
                anchors.leftMargin: mode.layout.progress.gap
                anchors.right: remaining.left
                anchors.rightMargin: mode.layout.progress.gap
                anchors.verticalCenter: parent.verticalCenter
                enabled: mode.media.canSeek && mode.hasTimeline
                value: mode.hasTimeline ? Math.min(1, mode.position / mode.trackLength) : 0
                maximum: 1
                step: mode.media.length > 0 ? mode.layout.progress.scrollStep / mode.media.length : 0
                animated: false  // the position moves by itself, a pixel at a time; a seek shows at once
                onMoved: v => {
                    mode.preview(v * mode.media.length);
                    if (!pressed)
                        seekDelay.restart();  // the wheel
                }
                onReleased: mode.seekNow()
            }
            StyledText {
                id: remaining
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: widest.advanceWidth
                horizontalAlignment: Text.AlignRight
                font.pixelSize: mode.layout.progress.timeSize
                font.features: {
                    "tnum": 1
                }
                color: palette.placeholderText
                text: mode.hasTimeline ? "-" + mode.clock(Math.ceil(Math.max(0, mode.trackLength - mode.position))) : mode.layout.progress.unknownTime
            }
        }

        // ---- controls, centred ----
        Item {
            id: controls
            width: 2 * mode.layout.controls.spacing + mode.layout.controls.size
            height: mode.layout.controls.playSize
            x: (stage.width - width) / 2
            y: stage.controlsCentre - height / 2

            SkipControl {
                id: previousControl
                anchors.verticalCenter: parent.verticalCenter
                x: 0
                back: true
                size: mode.layout.controls.size
                available: mode.media.canPrevious
                onClicked: Sys.mediaPrevious()
            }
            // play / pause: both glyphs, the one shown scaled up, the other down
            Item {
                id: playPause
                anchors.centerIn: parent
                width: mode.layout.controls.playSize
                height: width
                opacity: mode.media.canPlayPause ? 1 : mode.layout.controls.unavailableOpacity
                scale: playTap.pressed ? Config.motion.pressScale : 1
                Behavior on scale {
                    NumberAnimation {
                        duration: Config.motion.pressDuration
                        easing.type: Easing.OutCubic
                    }
                }
                Repeater {
                    model: [false, true]
                    delegate: Icon {
                        required property bool modelData
                        readonly property bool showing: modelData === mode.media.playing
                        anchors.fill: parent
                        name: modelData ? mode.layout.icons.pause : mode.layout.icons.play
                        color: palette.windowText
                        opacity: showing ? 1 : 0
                        scale: showing ? 1 : mode.layout.controls.swapScale
                        Behavior on opacity {
                            NumberAnimation {
                                duration: mode.layout.controls.swapDuration
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: mode.layout.controls.swapDuration
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
                HoverHandler {
                    enabled: mode.media.canPlayPause
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    id: playTap
                    enabled: mode.media.canPlayPause
                    onTapped: Sys.mediaPlayPause()
                }
            }
            SkipControl {
                id: nextControl
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width - mode.layout.controls.size
                size: mode.layout.controls.size
                available: mode.media.canNext
                onClicked: Sys.mediaNext()
            }
        }
    }
}
