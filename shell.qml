pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

import "island"
import "modes"
import "services"

// Entry point. One top-bar window holding the island. Everything shows in it: panels the user opens
// (clicks inside it or `qs ipc call island toggle <state>`), volume / brightness / microphone feedback
// (`qs ipc call osd ...`), low battery / charging / Wi-Fi / headphones alerts, messages and notifications.
// Activity queues them and picks the one on screen by priority (island.priority: what the user does
// interrupts what the system does); islandState follows it.
ShellRoot {
    id: root

    // ---- state ----
    // the mode on screen: Activity's pick; when nothing wants the island, idle (calm mode: the empty pill,
    // idle while hovered)
    readonly property string islandState: Activity.current ? Activity.current.kind : Activity.calm && !Activity.calmRevealed ? "calm" : "idle"
    // the open panel was opened from the keyboard (launcher Enter, IPC shortcut): it gets the keyboard
    // right away, and doesn't auto-close until the mouse has visited the island once (pinned)
    property bool keyboardOpened: false
    property bool pinned: false
    // a key press just closed/switched a mode: keep the keyboard until it's released (see keyCatcher)
    property bool keyHeld: false

    function open(name, byKeyboard) {
        // set first: the panel reads it (island.keyboardOpened) as it becomes active
        keyboardOpened = byKeyboard && name !== "" && name !== "idle";
        Activity.openPanel(name);
        keyboardOpened = byKeyboard && Activity.panel !== "";
        pinned = keyboardOpened;
    }
    function holdKeyboard() {
        keyHeld = true;
        keyCatcher.forceActiveFocus();
        keyHoldTimeout.restart();
    }

    // keyboard shortcuts: `qs ipc call island toggle search`
    IpcHandler {
        target: "island"
        function toggle(name: string): void {
            root.open(Activity.panel === name ? "idle" : name, true);
        }
        // the power off / restart goodbye, without powering off
        function goodbye(): void {
            Activity.previewGoodbye();
        }
        // calm mode on / off (until the fullscreen state changes), for a keyboard shortcut
        function calm(): void {
            Activity.toggleCalm();
        }
        // Focus (do not disturb) on / off, for a keyboard shortcut
        function focus(): void {
            Activity.setDoNotDisturb(!Activity.doNotDisturb);
        }
        // the music: "play-pause", "next", "previous"
        function media(action: string): void {
            if (action === "play-pause")
                Sys.mediaPlayPause();
            else if (action === "next")
                Sys.mediaNext();
            else if (action === "previous")
                Sys.mediaPrevious();
        }
    }

    // qmllint disable uncreatable-type
    PanelWindow {
        id: topBar
        screen: Quickshell.screens[0]
        WlrLayershell.layer: WlrLayer.Overlay
        // Keyboard, so panels never steal typing from the app you're in:
        //  - opened from the keyboard (or a closing key still held): Exclusive, you're already typing here
        //  - opened with the mouse: Exclusive too if island.clickTakesKeyboard (Escape closes it right away;
        //    the app gets the keyboard back when the panel closes), else OnDemand: your app keeps the
        //    keyboard until you click in the panel
        //  - no panel open (idle, feedback, notifications): None
        WlrLayershell.keyboardFocus: root.keyboardOpened || root.keyHeld ? WlrKeyboardFocus.Exclusive : Activity.panel === "" ? WlrKeyboardFocus.None : Config.island.clickTakesKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        // position/size
        exclusiveZone: Config.bar.height
        // constant, never animated: room for the tallest island
        implicitHeight: Config.island.maxHeight
        anchors {
            top: true
            left: true
            right: true
        }

        // style
        color: "transparent"

        // clicks on the transparent area fall through to windows below
        mask: Region {
            item: island
        }

        // blur behind the island (island.blur): the compositor blurs what's under this area, if it supports
        // it (ext-background-effect; niri does). Follows the island as it springs.
        BackgroundEffect.blurRegion: Config.island.blur ? blurArea : null
        Region {
            id: blurArea
            item: island
            radius: island.blurCorner
            topLeftRadius: island.attached ? 0 : island.blurCorner
            topRightRadius: island.attached ? 0 : island.blurCorner
        }

        // Takes focus while a closing key is still held, so niri doesn't hand that key to the window below
        // (Escape would make a fullscreen video exit fullscreen). Releases the keyboard on key up.
        Item {
            id: keyCatcher
            Keys.onReleased: event => {
                if (!event.isAutoRepeat)
                    root.keyHeld = false;
            }
        }
        Timer {
            id: keyHoldTimeout
            interval: Config.island.keyHoldTimeout
            onTriggered: root.keyHeld = false
        }

        // hovering pauses the timer of what's shown (feedback, notification)
        Binding {
            target: Activity
            property: "hovered"
            value: island.hovered
        }

        // every mode (modes/AllModes.qml); Island wires up their signals
        Island {
            id: island
            current: root.islandState
            keyboardOpened: root.keyboardOpened
            // attached to the top edge: no gap above it, only below
            y: topGap
            screenWidth: topBar.screen.width
            screenHeight: topBar.screen.height
            anchors.horizontalCenter: parent.horizontalCenter

            // a key press that switches modes calls holdKeyboard() first, so keyHeld says "from the keyboard"
            onRequestState: name => root.open(name, root.keyHeld)
            onHoldKeyboard: root.holdKeyboard()
            onHoveredChanged: {
                if (hovered)
                    root.pinned = false;
            }

            AllModes {}
        }
        // mouse-opened panels close collapseDelay after the mouse leaves (not autoClose ones, like search).
        // Only while the panel itself is on screen: covered by the volume, it waits.
        Timer {
            running: Activity.panelShown && !!island.activeMode && island.activeMode.autoClose && !island.hovered && !root.pinned && !Activity.draggingOut
            interval: Config.island.collapseDelay
            onTriggered: root.open("idle", false)
        }
    }

    // click outside to close (island.clickOutsideCloses): while a panel is open, a transparent full-screen
    // layer on the Top layer (under the island's Overlay one) takes clicks that miss the island and closes
    // the panel. A layer surface never hears about clicks outside itself, hence the separate window.
    // Mapped only while a panel is open, so it costs nothing otherwise. Fullscreen windows sit above the
    // Top layer in niri, so over a fullscreen app the click goes to the app instead.
    // One per screen: a click on another monitor closes the panel too.
    Variants {
        model: Quickshell.screens
        // qmllint disable uncreatable-type
        PanelWindow {
            required property ShellScreen modelData
            screen: modelData
            visible: Config.island.clickOutsideCloses && Activity.panel !== "" && !Activity.draggingOut
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-dismiss"
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: root.open("idle", false)
            }
        }
    }

    // rounded screen corners (config screenCorners), on every screen
    Variants {
        model: Quickshell.screens
        ScreenCorners {}
    }
}
