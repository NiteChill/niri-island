import QtQuick

import "../services"
import "../island"
import "../widgets"

// The notch while music plays, like the iPhone's compact "now playing": the cover at the left, the bars
// at the right in the cover's color, nothing in between (nowPlaying.width x height: a little bigger than
// the resting notch, which is calmer). It's the notch's base layer (Activity): it stays the whole
// time music plays, every alert covers it, then it comes back; paused, it stays nowPlaying.linger seconds.
// Clicking it opens the player (Activity.openNotch).
IslandMode {
    id: mode

    readonly property var layout: Config.nowPlaying
    readonly property real coverSize: layout.height - 2 * layout.coverInset

    belowMinimum: true
    implicitWidth: layout.width
    implicitHeight: layout.height

    // the cover pops in once on screen (appeared), from small
    property real coverPop: 1
    Behavior on coverPop {
        id: popBehavior
        SpringAnimation {
            spring: Config.spring(mode.layout.coverPop).spring
            damping: Config.spring(mode.layout.coverPop).damping
            epsilon: 0.001
        }
    }
    onActiveChanged: {
        if (active) {
            popBehavior.enabled = false;
            coverPop = layout.coverPopFrom;
            popBehavior.enabled = true;
        }
    }
    onAppeared: coverPop = 1

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: Activity.openNotch()
    }

    MediaCover {
        x: mode.layout.coverInset
        anchors.verticalCenter: parent.verticalCenter
        width: mode.coverSize
        height: mode.coverSize
        iconSize: mode.coverSize * mode.layout.noteScale
        // concentric with the notch's corner around it
        radius: Config.inner(Config.corner(Config.attached ? "attached" : "island", mode.layout.height), mode.layout.coverInset, mode.coverSize)
        scale: mode.coverPop
    }
    MediaBars {
        anchors.right: parent.right
        anchors.rightMargin: mode.layout.edge
        anchors.verticalCenter: parent.verticalCenter
        count: mode.layout.count
        barHeight: mode.layout.barHeight
        // moving once on screen, and still while it animates out (stopping then read as a jolt)
        running: (mode.active ? mode.hasAppeared : mode.onScreen) && Sys.media.playing
    }
}
