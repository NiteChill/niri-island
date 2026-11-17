import QtQuick

import "../services"
import "../island"
import "../widgets"

// Island mode (an activity, put up by Activity): music started, like the iPhone's compact "now playing":
// the cover at the far left (a rounded tile with room around it; it pops in), the bars at the far
// right in the cover's color, nothing in between. One line (island.restHeight), nowPlaying.width wide.
// Activity shows it only when music starts after a quiet spell (nowPlaying.quietGap: the next song of a
// playlist, or a resume after a short pause, doesn't). Clicking it opens the media panel.
IslandMode {
    id: mode

    readonly property var layout: Config.nowPlaying
    readonly property real restHeight: island ? island.restHeight : 0
    // the cover sits nowPlaying.coverInset from the edges (more than a badge's activity.inset: a picture
    // touching the island's rim looked crammed)
    readonly property real coverSize: restHeight - 2 * layout.coverInset

    implicitWidth: layout.width
    implicitHeight: restHeight

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

    TapHandler {
        onTapped: {
            Activity.dismiss("nowPlaying");
            mode.requestState("media");
        }
    }

    // centred: the island is never narrower than island.minWidth
    Item {
        x: (mode.width - mode.implicitWidth) / 2
        width: mode.implicitWidth
        height: mode.implicitHeight

        MediaCover {
            x: mode.layout.coverInset
            anchors.verticalCenter: parent.verticalCenter
            width: mode.coverSize
            height: mode.coverSize
            iconSize: mode.coverSize * mode.layout.noteScale
            scale: mode.coverPop
        }
        MediaBars {
            anchors.right: parent.right
            anchors.rightMargin: Config.activity.edge
            anchors.verticalCenter: parent.verticalCenter
            count: mode.layout.count
            barHeight: mode.layout.barHeight
            // moving once on screen, and still while it animates out (stopping then read as a jolt)
            running: (mode.active ? mode.hasAppeared : mode.onScreen) && Sys.media.playing
        }
    }
}
