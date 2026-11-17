import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Shapes

import "../services"
import "../island"
import "../widgets"

// Media panel, Apple's Dynamic Island "now playing" expanded:
//  - top row: the cover (rounded tile; a music note without one), the title in white over the artist in
//    grey, and in the top-right corner the bars (MediaBars) dancing in the cover's color while it plays
//  - the progress (only when the player gives the track's length): elapsed at the left, the bar (LevelSlider: drag to seek), the time left at the right
//  - the controls, centred: previous, play / pause (bigger; the two glyphs swap with a quick scale), next
// Keys: Space plays / pauses, Left / Right go to the previous / next track, Escape closes.
// Data and actions: Sys.media*; the position from Sys's anchor (mediaPositionNow / mediaRate), animated.
// Fullscreen (media.fullscreen): double-click an empty spot and the island grows to fill the screen; the
// bars fade, the cover flies to a big picture (its own proportions) and the title and artist grow under it,
// above the progress bar and the
// controls, which slide to the bottom of the screen and grow, over a very blurry copy of the picture (black
// without one). The badge at the top right, Escape or another double-click
// go back. Reset once the panel is gone.
// Ways in: the idle bars (idle.media), the launcher, `qs ipc call island toggle media`. Settings: media.*,
// media.padding (its own: more air than panel.padding), panel.width.
IslandMode {
    id: mode

    readonly property var layout: Config.media
    launcher: Config.media.launcher
    keyTarget: mode
    Keys.onSpacePressed: Sys.mediaPlayPause()
    Keys.onLeftPressed: previousControl.skip()
    Keys.onRightPressed: nextControl.skip()

    // the track shown: frozen while the panel animates out
    property var media: Sys.media
    readonly property real contentWidth: Config.panel.width - 2 * layout.padding
    readonly property real progressHeight: Math.max(Config.slider.height, elapsed.implicitHeight)

    implicitWidth: fullscreen ? screenWidth : Config.panel.width
    implicitHeight: fullscreen ? screenHeight : normalHeight
    // from the content's sizes (not a positioner: see CLAUDE.md)
    // no length from the player (YouTube in Zen/Firefox, live streams): no timeline to show or seek, and
    // the position it gives is meaningless (0): the progress row goes and the panel gets shorter
    readonly property bool hasTimeline: media.length > 0
    readonly property real normalHeight: 2 * layout.padding + layout.art.size + timelineRoom * (layout.progress.gapAbove + progressHeight) + layout.controls.gapAbove + layout.controls.playSize

    // ---- fullscreen ----
    readonly property var full: Config.media.fullscreen
    readonly property real screenWidth: island ? island.screenWidth : 0
    readonly property real screenHeight: island ? island.screenHeight : 0
    // back from fullscreen, the pointer is left outside the shrunken panel: it stays open until the
    // pointer comes back over it (or Escape / a click outside)
    autoClose: !fullscreen && !holdOpen
    property bool holdOpen: false
    Connections {
        target: mode.island
        function onHoveredChanged() {
            if (mode.island.hovered && !mode.fsTracking)
                mode.holdOpen = false;
        }
    }
    escapeCloses: !fullscreen
    onEscaped: setFullscreen(false)
    // follows the island's height (from the panel's to the screen's) from the moment fullscreen is asked
    // until the island is back at the panel's size: nothing changes while the panel only resizes itself
    property bool fsTracking: false
    // within half a device pixel of the screen counts as there: the spring's last sub-pixel creep moved
    // the picture and the controls by fractions of a pixel (a shimmer as it settled)
    readonly property real liveFs: !fsTracking || !active || !island || screenHeight <= normalHeight ? 0 : (screenHeight - island.height) * dpr < 0.5 ? 1 : Math.max(0, Math.min(1, (island.height - normalHeight) / (screenHeight - normalHeight)))
    // 0 = the panel, 1 = the whole screen: what the layout below blends with. Frozen while leaving.
    property real fs: 0
    onLiveFsChanged: if (!fullscreen && liveFs <= 0)
        Qt.callLater(stopTracking)
    function stopTracking() {
        if (!fullscreen && liveFs <= 0)
            fsTracking = false;
    }
    function setFullscreen(on) {
        if (on && (!full.enabled || !active))
            return;
        if (on)
            fsTracking = true;
        else if (fullscreen)
            holdOpen = true;
        fullscreen = on;
    }
    function blend(a, b) {
        return a + (b - a) * fs;
    }
    // the panel's own height now (riding the island's edge while the progress row comes or goes)
    readonly property real panelHeight: resizing && !fullscreen ? islandHeight : normalHeight

    // The length can arrive or go while the panel is open (Zen sends it once the page's second video
    // goes, often on a pause). Arriving: the panel takes the row's room at once and the island springs
    // to it, the controls riding the island's bottom edge (`resizing`: the content follows the island's
    // live height), then, once the island is there, the row fades and scales in (media.progress.fadeDuration,
    // from popFrom). Going: the row fades out first, then the island springs back, the controls riding up
    // with it. Closed: it just takes its state.
    property real timelineRoom: hasTimeline ? 1 : 0     // 0 / 1: the room it takes
    property real timelineShown: hasTimeline ? 1 : 0    // 0-1: how much it's shown
    property bool resizing: false
    // the island's live height, read only while resizing (each frame of its spring)
    readonly property real islandHeight: resizing && island ? island.height : 0
    // deferred: `resizing` can't change while islandHeight (which reads it) is being updated
    onIslandHeightChanged: Qt.callLater(settleCheck)
    function settleCheck() {
        if (!resizing || !island || Math.abs(island.height - fullHeight) > Config.island.revealTolerance)
            return;
        resizing = false;
        if (hasTimeline)
            rowIn.start();
    }
    onHasTimelineChanged: {
        rowIn.stop();
        rowOut.stop();
        if (!active) {
            resizing = false;
            timelineRoom = hasTimeline ? 1 : 0;
            timelineShown = timelineRoom;
        } else if (hasTimeline) {
            timelineRoom = 1;
            resizing = true;
            Qt.callLater(settleCheck);  // already there (it was fading out): straight to the fade-in
        } else {
            rowOut.duration = layout.progress.fadeDuration * timelineShown;
            rowOut.start();
        }
    }
    NumberAnimation {
        id: rowIn
        target: mode
        property: "timelineShown"
        to: 1
        duration: mode.layout.progress.fadeDuration
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: rowOut
        target: mode
        property: "timelineShown"
        to: 0
        easing.type: Easing.OutCubic
        onFinished: {
            mode.timelineRoom = 0;
            mode.resizing = true;
            Qt.callLater(mode.settleCheck);
        }
    }

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
    // position stops where it is, no more following the island's height), reset once gone.
    onActiveChanged: {
        if (active) {
            media = Qt.binding(() => Sys.media);
            fs = Qt.binding(() => liveFs);
        } else {
            media = media;
            fs = fs;
        }
        follow();
        resizing = false;
        if (active)
            snapRow();
    }
    onOnScreenChanged: {
        if (onScreen)
            return;
        snapRow();
        fullscreen = false;
        fsTracking = false;
        holdOpen = false;
        fs = 0;
    }
    function snapRow() {
        rowIn.stop();
        rowOut.stop();
        timelineRoom = hasTimeline ? 1 : 0;
        timelineShown = timelineRoom;
    }
    readonly property real trackLength: media.length
    onTrackLengthChanged: {
        if (trackLength > 0)
            rowLength = trackLength;
        if (!dragging)
            follow();
    }
    // the length the progress row shows: the last one known, so it stays as it was while fading out
    property real rowLength: media.length

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
                    color: Config.colors.text
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


    // Everything sits on a stage the panel's size that grows to the screen's with `fs`, centred in the
    // island (the mode is centred in it). Positions blend between the panel layout and the fullscreen one.
    Item {
        id: stage
        width: mode.blend(Config.panel.width, mode.screenWidth)
        height: mode.blend(mode.panelHeight, mode.screenHeight)
        x: (mode.width - width) / 2

        // double-click an empty spot: fullscreen on / off (not on the controls, the bar or the exit badge:
        // this handler also hears their taps). Only once the panel has settled (it no longer scales with
        // the island while it opens).
        TapHandler {
            enabled: mode.full.enabled
            onDoubleTapped: eventPoint => {
                if (mode.fitWeight > 0 || mode.onControl(eventPoint.position))
                    return;
                mode.setFullscreen(!mode.fullscreen);
            }
        }

        // ---- fullscreen backdrop: a very blurry copy of the cover / video thumbnail, black without one.
        // Exactly the island's rectangle, rounded like it (its corners morph into the screen's). Comes in
        // over the first part of the growth and goes over the last part of the way back
        // (fullscreen.topRowFade), while the top row does the reverse. The picture is decoded tiny
        // (backdrop.sampleSize), drawn a bit bigger than the island (backdrop.overscan: the blur's see-through
        // edges stay outside) and blurred. ----
        Item {
            id: backdrop
            visible: mode.fs > 0
            opacity: mode.full.topRowFade > 0 ? Math.min(1, mode.fs / mode.full.topRowFade) : 1
            width: visible && mode.island ? mode.island.width : 0
            height: visible && mode.island ? mode.island.height : 0
            x: (stage.width - width) / 2
            Item {
                id: backdropContent
                anchors.fill: parent
                visible: false
                layer.enabled: backdrop.visible
                Rectangle {
                    anchors.fill: parent
                    color: mode.full.background
                }
                // the previous track's until the next cover has loaded (no dip to black between tracks)
                SwapImage {
                    id: blurSource
                    anchors.centerIn: parent
                    width: parent.width * mode.full.backdrop.overscan
                    height: parent.height * mode.full.backdrop.overscan
                    source: mode.fullscreen || mode.fs > 0 ? mode.media.artUrl || "" : ""
                    sourceSize: Qt.size(mode.full.backdrop.sampleSize, mode.full.backdrop.sampleSize)
                }
                MultiEffect {
                    anchors.fill: blurSource
                    source: blurSource.current
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1
                    blurMax: mode.full.backdrop.blur
                    opacity: blurSource.ready ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: mode.full.imageFade
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                // darker, so the picture and the controls stand out from it
                Rectangle {
                    anchors.fill: parent
                    color: mode.full.background
                    opacity: blurSource.ready ? mode.full.backdrop.dim : 0
                }
                // a dark band at the bottom, so the controls read on a bright picture
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: mode.full.scrimHeight
                    visible: blurSource.ready
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Qt.alpha(mode.full.background, 0)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.alpha(mode.full.background, mode.full.scrimOpacity)
                        }
                    }
                }
            }
            // the island's own outline (smoothed corners; a plain rounded rectangle when the island is one)
            Item {
                id: backdropMask
                anchors.fill: parent
                visible: false
                layer.enabled: backdrop.visible
                Rectangle {
                    anchors.fill: parent
                    visible: !!mode.island && mode.island.plain
                    radius: mode.island ? Math.min(mode.island.corner, height / 2) : 0
                }
                Shape {
                    x: mode.island ? mode.island.drawnX : 0
                    y: mode.island ? mode.island.drawnY : 0
                    width: mode.island ? mode.island.drawnWidth : 0
                    height: mode.island ? mode.island.drawnHeight : 0
                    visible: !!mode.island && !mode.island.plain
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: -1
                        fillColor: Config.colors.text
                        PathSvg {
                            path: backdrop.visible && mode.island ? mode.island.shapePath : ""
                        }
                    }
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: backdropContent
                maskEnabled: true
                maskSource: backdropMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
        }

        // ---- top row: cover, title / artist, bars (stays where it was in the panel, fading out) ----
        // the cover, outside the row: with a picture it doesn't fade, it flies (hero, below)
        MediaCover {
            id: art
            x: topRow.x
            y: topRow.y
            width: mode.layout.art.size
            height: mode.layout.art.size
            iconSize: mode.layout.art.iconSize
            opacity: hero.ready ? (mode.fs > 0 ? 0 : 1) : topRow.opacity
            visible: opacity > 0
        }
        Item {
            id: topRow
            x: (stage.width - Config.panel.width) / 2 + mode.layout.padding
            y: mode.layout.padding
            width: mode.contentWidth
            height: mode.layout.art.size
            opacity: mode.full.topRowFade > 0 ? Math.max(0, 1 - mode.fs / mode.full.topRowFade) : (mode.fs > 0 ? 0 : 1)
            visible: opacity > 0

            MediaBars {
                id: bars
                // in the top-right corner, pushed in from the padding on both sides (cornerInset): small bars
                // tight in the corner looked cramped
                anchors.right: parent.right
                anchors.rightMargin: mode.layout.bars.cornerInset
                y: mode.layout.bars.cornerInset
                running: mode.onScreen && mode.media.playing && topRow.visible
            }

            // the panel's title and artist; in fullscreen they fly (flyTitle / flyArtist, below)
            Item {
                id: titles
                visible: mode.fs <= 0
                anchors.left: parent.left
                anchors.leftMargin: mode.layout.art.size + mode.layout.textGap
                anchors.right: bars.left
                anchors.rightMargin: mode.layout.textGap
                anchors.verticalCenter: parent.verticalCenter
                // from the text, not artist.visible: hidden during the fullscreen flight, this block's children
                // all read invisible, the title was centred alone (lower) and the flying text aimed there
                height: title.implicitHeight + (artist.text !== "" ? mode.layout.lineGap + artist.implicitHeight : 0)
                StyledText {
                    id: title
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: mode.layout.titleSize
                    font.weight: mode.layout.titleWeight
                    color: mode.media.active ? Config.colors.text : Config.colors.secondary
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
                    color: Config.colors.secondary
                    text: mode.media.active ? (mode.media.artist || mode.media.app || "") : ""
                }
            }
        }

        // the controls' and the progress bar's centres: in the panel, then at the bottom of the screen,
        // grown (fullscreen.controlsScale / progressScale)
        readonly property real controlsScale: mode.blend(1, mode.full.controlsScale)
        readonly property real progressScale: mode.blend(1, mode.full.progressScale)
        readonly property real controlsFullCentre: mode.screenHeight - mode.full.bottomMargin - mode.layout.controls.playSize * mode.full.controlsScale / 2
        readonly property real controlsCentre: mode.blend(mode.panelHeight - mode.layout.padding - mode.layout.controls.playSize / 2, controlsFullCentre)
        readonly property real controlsFullTop: controlsFullCentre - mode.layout.controls.playSize * mode.full.controlsScale / 2
        readonly property real progressFullCentre: controlsFullTop - mode.full.gap - mode.progressHeight * mode.full.progressScale / 2
        readonly property real progressCentre: mode.blend(mode.layout.padding + mode.layout.art.size + mode.layout.progress.gapAbove + mode.progressHeight / 2, progressFullCentre)
        // in fullscreen, what's above the progress bar (or the controls without one): the picture's room
        readonly property real pictureRoom: mode.hasTimeline ? progressFullCentre - mode.progressHeight * mode.full.progressScale / 2 : controlsFullTop
        // the picture, then the title and artist under it (fullscreen.text.*), centred together in that room
        readonly property real groupBottom: pictureRoom - mode.full.text.gapBelow
        readonly property bool artistShown: flyArtist.text !== ""
        readonly property real textFullHeight: flyTitle.implicitHeight + (artistShown ? mode.full.text.lineGap + flyArtist.implicitHeight : 0)
        readonly property real pictureFullRoom: hero.ready ? hero.fullHeight + mode.full.text.gapAbove : 0
        readonly property real groupTop: Math.max(0, (groupBottom - pictureFullRoom - textFullHeight) / 2)
        readonly property real textFullTop: groupTop + pictureFullRoom
        // The title / artist's height on the way: they ride the picture's bottom edge (a straight line from
        // the panel let the title climb onto the shrinking picture on the way back), under it until the last
        // fullscreen.text.riseShare of the way, then slide up beside the small cover. `from`: where it is in
        // the panel; `below`: how far under the title it sits in fullscreen (the artist).
        function flyY(from, below) {
            if (!hero.ready)
                return mode.blend(from, textFullTop + below);
            const u = mode.full.text.riseShare > 0 ? Math.min(1, mode.fs / mode.full.text.riseShare) : 1;
            const coverBottom = art.y + art.height;
            return hero.y + hero.height + (from - coverBottom) * (1 - u) + (mode.full.text.gapAbove + below) * u;
        }
        // ...and sideways: while they rise beside the cover, they also keep to the right of the picture
        // (textGap from it, as in the panel), so they never cross it. `toLeft`: the left edge in
        // fullscreen, from the screen's centre.
        function flyX(toLeft) {
            const straight = width / 2 + mode.blend(textLeft - width / 2, toLeft);
            if (!hero.ready)
                return straight;
            const u = mode.full.text.riseShare > 0 ? Math.min(1, mode.fs / mode.full.text.riseShare) : 1;
            // squared: the pull to the side lasts a little longer than the rise (they never cross the picture)
            const w = u * u;
            return straight * w + Math.max(straight, hero.x + hero.width + mode.layout.textGap) * (1 - w);
        }
        // the panel's text block, in stage coordinates (where the flight starts)
        readonly property real textLeft: topRow.x + titles.x
        readonly property real textTop: topRow.y + titles.y

        // ---- the picture's soft shadow (fullscreen.art.shadow): under it, the same size and corner, coming in
        // with the growth (none at the panel's size, so the swap with the small cover doesn't show) ----
        RectangularShadow {
            visible: hero.visible && mode.full.art.shadow.opacity > 0
            x: hero.x
            y: hero.y + mode.full.art.shadow.offset * mode.fs
            width: hero.width
            height: hero.height
            radius: hero.corner
            blur: mode.full.art.shadow.blur * mode.fs
            spread: mode.full.art.shadow.spread * mode.fs
            color: Qt.alpha(mode.full.background, mode.full.art.shadow.opacity * mode.fs)
        }

        // ---- the picture in fullscreen: the cover flies from its spot in the panel to a big picture with
        // its own proportions (fullscreen.art.heightShare of the screen's height, never wider than the
        // progress row), centred in the room above the progress bar (or at the left: fullscreen.art.position),
        // and back the same way. Square-cropped like the small cover at the start, so the swap doesn't show.
        // Only with a picture (without one the small cover fades with the top row). ----
        Item {
            id: hero
            readonly property bool ready: heroImage.ready
            // a new track's picture with other proportions (a video after an album): the picture springs to
            // its new shape (fullscreen.art.resize), the text below riding along; jumps outside fullscreen
            property real ratio: heroImage.ratio
            Behavior on ratio {
                enabled: mode.fs > 0
                SpringAnimation {
                    spring: Config.spring(mode.full.art.resize).spring
                    damping: Config.spring(mode.full.art.resize).damping
                    epsilon: 0.0005
                }
            }
            // never taller than the room the title and artist leave it
            readonly property real fullHeight: Math.max(0, Math.min(mode.screenHeight * mode.full.art.heightShare, (mode.screenWidth - 2 * mode.full.sideMargin) / ratio, stage.groupBottom - mode.full.text.gapAbove - stage.textFullHeight))
            readonly property real fullWidth: fullHeight * ratio
            // left edge in fullscreen, from the screen's centre (the stage's centre at every step)
            readonly property real fullLeft: mode.full.art.position === "left" ? mode.full.sideMargin - mode.screenWidth / 2 : -fullWidth / 2
            readonly property real fullTop: stage.groupTop
            // the small cover's corner, growing into the island's corner style at full size
            readonly property real corner: mode.blend(Config.corner("tile", mode.layout.art.size), Config.corner("island", Math.min(fullWidth, fullHeight)))
            visible: ready && mode.fs > 0
            width: mode.blend(mode.layout.art.size, fullWidth)
            height: mode.blend(mode.layout.art.size, fullHeight)
            x: stage.width / 2 + mode.blend(art.x - stage.width / 2, fullLeft)
            y: mode.blend(art.y, fullTop)
            // loaded while the panel is on screen, so it's ready when the flight starts; a new track's
            // picture replaces the previous one once loaded (no blank frame, no layout jump meanwhile)
            SwapImage {
                id: heroImage
                anchors.fill: parent
                source: mode.onScreen && mode.full.enabled ? mode.media.artUrl || "" : ""
                sourceSize: Qt.size(0, mode.screenHeight * mode.full.art.heightShare * mode.dpr)
                mipmap: true
            }
            // smoothed corners like the island's: the small cover's corner, growing into the island's corner
            // style at full size
            Shape {
                id: heroMask
                anchors.fill: parent
                visible: false
                // always on: switched on together with the picture, the mask drew nothing (tested)
                layer.enabled: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillColor: Config.colors.text
                    PathSvg {
                        path: hero.visible ? Config.roundedRectPath(hero.width, hero.height, hero.corner, Config.island.cornerSmoothing) : ""
                    }
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: heroImage.current
                maskEnabled: true
                maskSource: heroMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
        }


        // ---- the title and artist in fullscreen: they grow out of the panel's text (fullscreen.text.*Scale)
        // to sit under the picture, centred (or at the left with it), on the picture's flight. Drawn at the
        // full size and scaled down at the start, so they're sharp once there. ----
        StyledText {
            id: flyTitle
            // the size it reaches, from the panel's size
            readonly property real grow: mode.full.text.titleScale
            readonly property real toWidth: Math.min(implicitWidth, mode.screenWidth - 2 * mode.full.sideMargin)
            // left edge at the end, from the screen's centre (the stage's at every step), like the picture
            readonly property real toLeft: mode.full.art.position === "left" ? mode.full.sideMargin - mode.screenWidth / 2 : -toWidth / 2
            visible: mode.fs > 0 && text !== ""
            font.pixelSize: mode.layout.titleSize * grow
            font.weight: mode.layout.titleWeight
            color: title.color
            text: title.text
            elide: Text.ElideRight
            transformOrigin: Item.TopLeft
            scale: mode.blend(1 / grow, 1)
            width: mode.blend(titles.width * grow, toWidth)
            x: stage.flyX(toLeft)
            y: stage.flyY(stage.textTop + title.y, 0)
        }
        StyledText {
            id: flyArtist
            // the size it reaches, from the panel's size
            readonly property real grow: mode.full.text.artistScale
            readonly property real toWidth: Math.min(implicitWidth, mode.screenWidth - 2 * mode.full.sideMargin)
            // left edge at the end, from the screen's centre (the stage's at every step), like the picture
            readonly property real toLeft: mode.full.art.position === "left" ? mode.full.sideMargin - mode.screenWidth / 2 : -toWidth / 2
            visible: mode.fs > 0 && text !== ""
            font.pixelSize: mode.layout.artistSize * grow
            color: Config.colors.secondary
            text: artist.text
            elide: Text.ElideRight
            transformOrigin: Item.TopLeft
            scale: mode.blend(1 / grow, 1)
            width: mode.blend(titles.width * grow, toWidth)
            x: stage.flyX(toLeft)
            y: stage.flyY(stage.textTop + artist.y, flyTitle.implicitHeight + mode.full.text.lineGap)
        }

        // ---- progress: elapsed, bar, time left ----
        Item {
            id: progress
            visible: mode.timelineShown > 0
            opacity: mode.timelineShown
            // the row's own width grows too (the bar gets longer, not only bigger)
            width: mode.blend(mode.contentWidth, (mode.screenWidth - 2 * mode.full.sideMargin) / mode.full.progressScale)
            height: mode.progressHeight
            x: (stage.width - width) / 2
            y: stage.progressCentre - height / 2
            scale: (mode.layout.progress.popFrom + (1 - mode.layout.progress.popFrom) * mode.timelineShown) * stage.progressScale

            TextMetrics {
                id: widest
                font: elapsed.font
                text: "-" + mode.clock(Math.max(mode.rowLength, 600)).replace(/[0-9]/g, "0")
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
                color: Config.colors.secondary
                text: mode.media.active ? mode.clock(mode.second) : ""
            }
            LevelSlider {
                id: bar
                anchors.left: elapsed.right
                anchors.leftMargin: mode.layout.progress.gap
                anchors.right: remaining.left
                anchors.rightMargin: mode.layout.progress.gap
                anchors.verticalCenter: parent.verticalCenter
                enabled: mode.media.canSeek && mode.hasTimeline
                value: mode.rowLength > 0 ? Math.min(1, mode.position / mode.rowLength) : 0
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
                color: Config.colors.secondary
                text: mode.media.active && mode.rowLength > 0 ? "-" + mode.clock(Math.ceil(Math.max(0, mode.rowLength - mode.position))) : ""
            }
        }

        // ---- controls, centred ----
        Item {
            id: controls
            width: 2 * mode.layout.controls.spacing + mode.layout.controls.size
            height: mode.layout.controls.playSize
            x: (stage.width - width) / 2
            y: stage.controlsCentre - height / 2
            scale: stage.controlsScale

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
                        color: Config.colors.text
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

        // ---- leave fullscreen: a soft round badge in the top-right corner, concentric with the screen's ----
        Badge {
            id: exitBadge
            // fades in over the end of the growth (the share the top row takes to fade at its start)
            opacity: mode.full.topRowFade > 0 ? Math.max(0, (mode.fs - 1 + mode.full.topRowFade) / mode.full.topRowFade) : (mode.fs >= 1 ? 1 : 0)
            visible: opacity > 0
            height: mode.full.exit.size
            x: stage.width - mode.full.exit.margin - width
            y: mode.full.exit.margin
            outerCorner: mode.island ? mode.island.screenCorner : 0
            inset: mode.full.exit.margin
            icon: mode.full.exit.icon
            glyphSize: mode.full.exit.iconSize
            clickable: mode.fullscreen
            onClicked: mode.setFullscreen(false)
        }
    }
    // a point on the stage over something clickable (the double-click ignores those)
    function onControl(pos) {
        const items = [controls, exitBadge];
        if (progress.visible)
            items.push(progress);
        for (const item of items) {
            if (item.visible && item.contains(item.mapFromItem(stage, pos.x, pos.y)))
                return true;
        }
        return false;
    }
}
