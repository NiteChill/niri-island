pragma ComponentBehavior: Bound

import QtQuick

import "../services"

// The "now playing" bars (Apple's little waveform): a few rounded bars, centred, that follow the music while it
// plays (Sys.mediaLevels, from cava: bass at the left, treble at the right) and settle low when it's paused.
// Without cava they dance on their own. They only move while `running`: the owner sets it to "playing and on
// screen"; each running MediaBars counts itself in Sys.mediaLevelUsers, so cava runs only while one is shown.
// Settings: media.bars (the panel), idle.media (the idle island).
Item {
    id: bars

    property int count: Config.media.bars.count
    property real barWidth: Config.media.bars.width
    property real gap: Config.media.bars.gap
    property real barHeight: Config.media.bars.height
    property color tint: Sys.mediaColor
    Behavior on tint {
        ColorAnimation {
            duration: Config.motion.colorFade
        }
    }
    property bool running: false
    onRunningChanged: Sys.mediaLevelUsers += running ? 1 : -1
    Component.onCompleted: if (running) Sys.mediaLevelUsers += 1
    Component.onDestruction: if (running) Sys.mediaLevelUsers -= 1

    // real levels: bar i takes the band at the same place across the spectrum
    readonly property bool live: running && Sys.mediaLevelsLive
    onLiveChanged: {
        if (live || running)
            return;
        for (let i = 0; i < row.count; i++) {
            const bar = row.itemAt(i);
            if (bar)
                bar.level = Config.media.bars.restLevel;
        }
    }
    // per cava frame, the share of the way a bar moves toward its band: 95 % of the way (3 time constants)
    // within media.bars.ease
    readonly property real follow: 1 - Math.exp(-3 * 1000 / Config.media.bars.framerate / Math.max(1, Config.media.bars.ease))
    function band(i) {
        const ls = Sys.mediaLevels, n = ls.length;
        if (n === 0)
            return 0;
        return ls[count > 1 ? Math.round(i * (n - 1) / (count - 1)) : Math.floor(n / 2)];
    }

    implicitWidth: count * barWidth + Math.max(0, count - 1) * gap
    implicitHeight: barHeight

    Timer {
        id: beat
        running: bars.running && !bars.live
        repeat: true
        triggeredOnStart: true
        interval: Config.media.bars.beat
        onTriggered: {
            for (let i = 0; i < row.count; i++) {
                const bar = row.itemAt(i);
                if (bar)
                    bar.level = Config.media.bars.minLevel + Math.random() * (1 - Config.media.bars.minLevel);
            }
        }
        onRunningChanged: {
            if (running || bars.live)
                return;
            for (let i = 0; i < row.count; i++) {
                const bar = row.itemAt(i);
                if (bar)
                    bar.level = Config.media.bars.restLevel;
            }
        }
    }

    Repeater {
        id: row
        model: bars.count
        delegate: Rectangle {
            required property int index
            id: bar
            property real level: Config.media.bars.restLevel
            // live: the band, never below the paused height; each of cava's frames moves the bar part of the
            // way toward it (bars.follow: most of the way within media.bars.ease = calmer). Done per frame
            // instead of an animation: an animation kept the window redrawing at 60 fps on top of cava's
            // frames (measured 2026-11-15: 119 -> 55 CPU ticks per 9 s with the idle bars dancing)
            readonly property real liveLevel: Config.media.bars.restLevel + bars.band(index) * (1 - Config.media.bars.restLevel)
            onLiveLevelChanged: if (bars.live)
                level += (liveLevel - level) * bars.follow
            Behavior on level {
                enabled: !bars.live
                NumberAnimation {
                    duration: bars.live ? Config.media.bars.ease : Config.media.bars.beat
                    easing.type: bars.live ? Easing.OutQuad : Easing.InOutSine
                }
            }
            x: index * (bars.barWidth + bars.gap)
            width: bars.barWidth
            height: Math.max(width, level * bars.barHeight)
            anchors.verticalCenter: parent.verticalCenter
            radius: width / 2
            antialiasing: true
            color: bars.tint
        }
    }
}
