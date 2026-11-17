import QtQuick

import "../services"
import "../island"
import "../widgets"

// The resting island: clock (then the music bars, idle.media.left) on the left, status icons (Bluetooth,
// Wi-Fi, battery) on the right: what's going on at the left, the machine at the right. Headphones have no
// icon (their alert says it; 2026-11-15). Charging = a bolt, power saver = a plus, cut into the battery's end (idle.battery.badge).
// Clicking the clock, the music bars, Bluetooth, Wi-Fi or battery opens their panel. Clicking the empty middle opens quick settings (idle.middleOpensQuickSettings; no hover look on
// purpose, the onboarding explains it).
IslandMode {
    id: mode

    trOverride: Config.idle.transition
    // once open, lay out at the island's live width: the clock and icons ride its edges as it resizes
    followIsland: true

    // Natural size only. Must not depend on `width`, or you get a loop.
    readonly property real restHeight: island ? island.restHeight : 0

    // width the icon row is heading to: the sum of the slots' targets, not icons.width (their real width
    // animates, with the same spring as the island, so a new icon's space opens right where it goes)
    readonly property real iconsWidth: {
        let w = 0;
        for (const slot of icons.children)
            w += slot.targetRoom;
        return w;
    }

    implicitWidth: Config.island.pillInset + Config.island.pillPadding + clock.width + leftMusic.targetRoom + Config.island.minGap + iconsWidth + Config.island.pillInset
    implicitHeight: restHeight

    // the clock, in a pill like the status icons: click opens the time panel. island.pillInset from the
    // left edge, like the icons from the right one, so the pill's gap is the same on every side.
    // music stopped or paused a moment ago: the bars stay until idle.media.linger runs out
    property bool mediaRecent: false
    readonly property bool mediaPlaying: Sys.media.playing
    Component.onCompleted: mediaRecent = mediaPlaying
    onMediaPlayingChanged: {
        if (mediaPlaying) {
            mediaLinger.stop();
            mediaRecent = true;
        } else
            mediaLinger.restart();
    }
    Timer {
        id: mediaLinger
        interval: Config.idle.media.linger * 1000
        onTriggered: mode.mediaRecent = false
    }

    // music: the little bars (white: the island stays calm; idle.media.coverColor = the cover's color),
    // moving while it plays, resting once paused or finished; they stay idle.media.linger after that, so
    // a click on them (the media panel) starts it again. Only while a player is still there. One slot per
    // side; idle.media.left picks which one is used.
    readonly property bool musicShown: Config.idle.media.show && Sys.media.active && (Sys.media.playing || mediaRecent)
    // (an inline component can't see this file's ids: the instances pass `shown`, `islandActive` (on screen,
    // so the bars keep moving while the idle island animates out), the click)
    component MusicSlot: IconSlot {
        id: musicSlot
        property bool islandActive
        clickable: true
        MediaBars {
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            count: Config.idle.media.count
            barWidth: Config.idle.media.barWidth
            gap: Config.idle.media.gap
            barHeight: Config.idle.media.height
            tint: Config.idle.media.coverColor ? Sys.mediaColor : Config.colors.text
            running: musicSlot.shown && musicSlot.islandActive && Sys.media.playing && Config.idle.media.animate
        }
    }

    Row {
        id: leftIcons
        x: Config.island.pillInset
        anchors.verticalCenter: parent.verticalCenter
        height: mode.restHeight - 2 * Config.island.pillInset
        IconSlot {
            id: clockSlot
            shown: true
            clickable: true
            onClicked: mode.requestState("time")
            Clock {
                id: clock
            }
        }
        // right after the clock (the slot's gap goes after it, toward the middle)
        MusicSlot {
            id: leftMusic
            shown: mode.musicShown && Config.idle.media.left
            islandActive: mode.onScreen
            gap: Config.island.spacing
            onClicked: mode.requestState("media")
        }
    }

    // the empty middle, top to bottom: opens quick settings
    Item {
        visible: Config.idle.middleOpensQuickSettings
        anchors.left: leftIcons.right
        anchors.right: icons.left
        height: parent.height
        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: mode.requestState("quickSettings")
        }
    }

    Row {
        id: icons
        anchors.right: parent.right
        anchors.rightMargin: Config.island.pillInset
        anchors.verticalCenter: parent.verticalCenter
        // no Row spacing: each slot carries its own gap after it, so the spacing opens/closes with the icon
        // (battery is always shown and last, so it has no gap)
        // fixed to the resting size so the pills don't stretch while the island morphs
        height: mode.restHeight - 2 * Config.island.pillInset

        MusicSlot {
            shown: mode.musicShown && !Config.idle.media.left
            islandActive: mode.onScreen
            gap: Config.island.spacing
            onClicked: mode.requestState("media")
        }
        // a Bluetooth device is connected (headphones and speakers too: they have no icon of their own)
        IconSlot {
            shown: Config.idle.bluetooth.show && (Sys.bluetooth.otherConnected || Sys.bluetooth.audioConnected)
            gap: Config.island.spacing
            clickable: true
            onClicked: mode.requestState("bluetooth")
            Bluetooth {}
        }
        IconSlot {
            shown: Sys.wifi.connected
            gap: Config.island.spacing
            clickable: true
            onClicked: mode.requestState("wifi")
            Wifi {}
        }
        IconSlot {
            shown: true
            clickable: true
            onClicked: mode.requestState("battery")
            // like the iPhone: charging = a bolt, power saver = a plus, centred on the battery's right end and cut
            // into it (idle.battery.badge); the bolt wins when both
            CutoutBadge {
                readonly property var cfg: Config.idle.battery.badge
                readonly property bool bolt: cfg.charging && Sys.battery.charging
                readonly property bool plus: cfg.saver && Sys.battery.profile === "powerSaver"
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                height: parent ? parent.height : 0
                width: implicitWidth
                shown: bolt || plus
                centered: true
                icon: bolt ? cfg.chargingIcon : cfg.saverIcon
                size: bolt ? cfg.chargingSize : cfg.saverSize
                overhangX: size / 2 + cfg.offset
                gap: cfg.gap
                contentWidth: Config.idle.battery.size
                contentHeight: idleBattery.drawnHeight
                Battery {
                    id: idleBattery
                    tint: Sys.battery.idleColor
                }
            }
        }
    }
}
