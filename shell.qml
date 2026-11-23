pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

import "island"
import "modes"
import "surfaces"
import "widgets"
import "services"

// Entry point. One window across the top of the screen (the whole screen tall, but it only takes the
// pointer where something is drawn: see `mask`) holding, bottom to top:
//  - the bar (surfaces/Bar.qml): the focused app and the workspaces at the left, the tray, status icons,
//    quick settings and the clock at the right, each opening its dropdown
//  - the notifications (surfaces/NotificationStack.qml): cards sliding in at the top right, the center
//    under the clock's calendar
//  - the dropdowns' card (surfaces/Dropdown.qml), under the bar item it was opened from
//  - the notch (island/Island.qml + modes/AllModes.qml): what happens now (volume, alerts, the music) and
//    what it holds (the shelf: drop files on it); a click opens the player or the shelf
// Activity says what is open and what the notch shows; `qs ipc call island toggle <name>` opens anything.
ShellRoot {
    id: root

    // ---- state ----
    // the notch's mode: Activity's pick, else the notch at rest
    readonly property string islandState: Activity.current ? Activity.current.kind : "rest"
    // the open dropdown was opened from the keyboard (launcher Enter, IPC shortcut): it gets the keyboard
    // right away (quick settings selects its first switch)
    property bool keyboardOpened: false
    // a key press just closed/switched a mode: keep the keyboard until it's released (see keyCatcher)
    property bool keyHeld: false

    function open(name, byKeyboard) {
        // set first: the dropdown reads it (island.keyboardOpened) as it becomes active
        keyboardOpened = byKeyboard && name !== "" && name !== "idle";
        Activity.open(name);
        keyboardOpened = byKeyboard && Activity.anyOpen;
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
            root.open(Activity.isOpen(name) ? "idle" : name, true);
        }
        // the power off / restart goodbye, without powering off
        function goodbye(): void {
            Activity.previewGoodbye();
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
        WlrLayershell.namespace: "quickshell-bar"
        // Keyboard, so dropdowns never steal typing from the app you're in:
        //  - opened from the keyboard (or a closing key still held): Exclusive, you're already typing here
        //  - opened with the mouse: Exclusive too if island.clickTakesKeyboard (Escape closes it right away;
        //    the app gets the keyboard back when it closes), else OnDemand: your app keeps the keyboard
        //    until you click in it
        //  - nothing open (the notch's pop-ups, the cards): None
        WlrLayershell.keyboardFocus: root.keyboardOpened || root.keyHeld ? WlrKeyboardFocus.Exclusive : !Activity.anyOpen ? WlrKeyboardFocus.None : Config.island.clickTakesKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        // the bar's height is kept free for it; the window itself is the whole screen tall (constant, never
        // resized: the dropdowns and the cards hang below the bar)
        exclusiveZone: Config.bar.height
        implicitHeight: screen ? screen.height : 0
        anchors {
            top: true
            left: true
            right: true
        }
        color: "transparent"

        // clicks on the transparent area fall through to windows below: only what's drawn takes them
        mask: Region {
            item: barArea
            Region {
                item: island
            }
            Region {
                item: dropArea
            }
            Region {
                item: bridgeArea
            }
            Region {
                item: stackArea
            }
            Region {
                item: tabsArea
            }
            Region {
                item: dropHold
            }
        }
        Item {
            id: barArea
            width: bar.visible ? topBar.width : 0
            height: bar.visible ? Config.bar.height : 0
        }
        Item {
            id: dropArea
            x: dropdown.inputRect.x
            y: dropdown.y + dropdown.inputRect.y
            width: dropdown.inputRect.width
            height: dropdown.inputRect.height
        }
        // the gap between the bar and an open dropdown's card takes the pointer too, so moving from an icon
        // down into its dropdown never passes over "nothing" (where the pointer would leave the window)
        Item {
            id: bridgeArea
            x: dropArea.x
            y: Config.bar.height
            width: dropArea.width
            height: dropArea.height > 0 && bar.visible ? Math.max(0, dropArea.y - Config.bar.height) : 0
        }
        Item {
            id: tabsArea
            x: tabs.x
            y: tabs.y
            width: tabs.visible ? tabs.width : 0
            height: tabs.visible ? tabs.height : 0
        }
        Item {
            id: stackArea
            x: stack.inputRect.x
            y: stack.inputRect.y
            width: stack.inputRect.width
            height: stack.inputRect.height
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

        Bar {
            id: bar
            width: parent.width
            window: topBar
            card: dropArea.width > 0 ? Qt.rect(dropArea.x, dropArea.y, dropArea.width, dropArea.height) : Qt.rect(0, 0, 0, 0)
            notch: Qt.rect(island.x, island.y, island.width, island.height)
            onEmptyClicked: root.open("idle", false)
        }

        // the banners at the top right, under the bar, like macOS (the center hangs under the calendar)
        NotificationStack {
            id: stack
            x: topBar.width - Config.notifications.margin - width
            y: Config.bar.height + Config.notifications.gapBelow
            onHoldKeyboard: root.holdKeyboard()
            under: Activity.center && dropArea.width > 0 ? Qt.rect(dropArea.x, dropArea.y, dropArea.width, dropArea.height) : Qt.rect(0, 0, 0, 0)
            windowHeight: topBar.height
        }

        Dropdown {
            id: dropdown
            y: Config.bar.height + Config.panel.gap
            width: parent.width
            bar: bar
            screenWidth: topBar.width
            screenHeight: topBar.height
            keyboardOpened: root.keyboardOpened
            extraModes: island.modeList
            onRequestState: name => root.open(name, root.keyHeld)
            onHoldKeyboard: root.holdKeyboard()
        }

        // Drop files on the notch: it becomes the drop zone (DropMode), the shelf takes them (Sys.shelfAdd).
        // Not the notch's own size: dragged over the big open shelf, the notch shrank to the drop zone, out
        // from under the pointer, the drag "left", the shelf grew back under it, the drag "entered"... a
        // loop. While a drag is over it, it keeps the size the notch had when the drag came (or the drop
        // zone's, if bigger), it's in the window's input (dropArea), and a drag must stay out
        // island.drop.leaveDelay before it counts as gone.
        DropArea {
            id: dropZone
            property real heldW: 0
            property real heldH: 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: island.y
            width: Activity.dropping ? heldW : island.width
            height: Activity.dropping ? heldH : island.height
            onEntered: drag => {
                dropLeave.stop();
                if (!Activity.dropping) {
                    heldW = Math.max(island.width, Config.island.drop.width);
                    heldH = Math.max(island.height, Config.island.drop.height);
                }
                drag.accept(Qt.CopyAction);
                Activity.dropping = true;
            }
            onExited: dropLeave.restart()
            onDropped: drop => {
                dropLeave.stop();
                Sys.shelfAdd(drop.urls);
                drop.accept(Qt.CopyAction);
                Activity.dropping = false;
            }
            Timer {
                id: dropLeave
                interval: Config.island.drop.leaveDelay
                onTriggered: Activity.dropping = false
            }
        }
        Item {
            id: dropHold
            x: dropZone.x
            y: dropZone.y
            width: Activity.dropping ? dropZone.width : 0
            height: Activity.dropping ? dropZone.height : 0
        }

        // the open notch's tabs (the player / the shelf, when both have something): a small pill of its
        // own under the notch, riding its bottom edge
        NotchTabs {
            id: tabs
            anchors.horizontalCenter: parent.horizontalCenter
            y: island.y + island.height + Config.island.tabs.gap
        }

        // hovering pauses the timer of what's shown
        Binding {
            target: Activity
            property: "hovered"
            value: island.hovered
        }

        // the notch: every notch mode (modes/AllModes.qml); Island wires up their signals
        Island {
            id: island
            current: root.islandState
            attached: Config.attached
            minWidth: Config.island.minWidth
            restWidth: Config.island.rest.width
            keyboardOpened: root.keyboardOpened
            // glued to the top edge, or floating island.gap below it
            y: attached ? 0 : Config.island.gap
            screenWidth: topBar.width
            screenHeight: topBar.height
            anchors.horizontalCenter: parent.horizontalCenter
            // the launcher (one of the notch's panels) lists the dropdowns too
            extraModes: dropdown.surface.modeList

            // a key press that switches modes calls holdKeyboard() first, so keyHeld says "from the keyboard"
            onRequestState: name => root.open(name, root.keyHeld)
            onHoldKeyboard: root.holdKeyboard()

            AllModes {}

        }
    }

    // click outside to close (island.clickOutsideCloses): while something is open, a transparent
    // full-screen layer on the Top layer (under the bar's Overlay one) takes clicks that miss it and closes
    // it. A layer surface never hears about clicks outside itself, hence the separate window. Mapped only
    // while something is open, so it costs nothing otherwise. One per screen.
    Variants {
        model: Quickshell.screens
        // qmllint disable uncreatable-type
        PanelWindow {
            required property ShellScreen modelData
            screen: modelData
            visible: Config.island.clickOutsideCloses && Activity.anyOpen && !Activity.draggingOut
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
