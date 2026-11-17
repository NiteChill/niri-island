import QtQuick

import "../services"

// Pill around a status icon in the idle island, plus the gap after it (`gap`).
// Appearing: the slot's room springs open first (same spring as the island growing, so the space opens
// exactly where the icon goes while the island grows), then the icon fades/scales in.
// Disappearing: the icon fades out, then the room springs closed (island shrink spring).
// Optional hover + click.
Item {
    id: slot

    // API
    property bool shown: false          // does the icon want to be there?
    property bool clickable: false
    property real gap: 0                // empty space kept after the pill (spacing to the next icon)
    default property alias content: holder.data
    signal clicked

    // internal state
    property bool occupying: false      // wants space in the layout
    property bool revealed: false       // content is visible (latched: stays on if the room later wobbles)
    readonly property real pillWidth: holder.childrenRect.width + 2 * Config.island.pillPadding
    // the width this slot is heading to; read by the island layout (instant, unlike `room`)
    readonly property real targetRoom: occupying ? pillWidth + gap : 0
    // the animated width actually taken in the row
    property real room: 0
    readonly property bool readyToReveal: shown && occupying && room >= targetRoom - Config.island.revealTolerance

    visible: occupying || room > 0
    width: room
    height: parent ? parent.height : implicitHeight
    implicitWidth: targetRoom
    implicitHeight: holder.childrenRect.height
    clip: true

    // direction is picked before the animation starts (see the CLAUDE.md animation gotchas)
    onTargetRoomChanged: {
        if (!_ready)
            return;
        const s = Config.spring(targetRoom > room ? Config.island.expand : Config.island.shrink);
        roomAnim.stop();
        roomAnim.spring = s.spring;
        roomAnim.damping = s.damping;
        roomAnim.to = targetRoom;
        roomAnim.start();
    }
    SpringAnimation {
        id: roomAnim
        target: slot
        property: "room"
        epsilon: 0.5
    }

    onShownChanged: {
        if (shown)
            occupying = true;
        else
            revealed = false;
    }
    onReadyToRevealChanged: {
        if (readyToReveal)
            revealed = true;
    }

    property bool _ready: false
    Component.onCompleted: {
        occupying = shown;
        revealed = shown;
        room = targetRoom;
        _ready = true;
    }

    // pill-shaped hover highlight, the size of the pill (not the gap); concentric with the resting island's
    // corner, island.pillInset inside it (see Config.inner)
    Rectangle {
        width: slot.pillWidth
        height: parent.height
        radius: Config.inner(Config.restCorner, Config.island.pillInset, height)
        color: Config.colors.text
        opacity: slot.clickable && hover.hovered ? Config.idle.hoverOpacity : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.motion.hoverFade }
        }

        // input is only live once the icon is actually visible (and only over the pill, not the gap)
        HoverHandler {
            id: hover
            enabled: slot.clickable && slot.revealed
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: slot.clickable && slot.revealed
            onTapped: slot.clicked()
        }
    }

    Item {
        id: holder
        x: Config.island.pillPadding
        width: childrenRect.width
        height: parent.height

        opacity: slot.revealed ? 1 : 0
        scale: Config.idle.revealScale + (1 - Config.idle.revealScale) * opacity

        Behavior on opacity {
            NumberAnimation { duration: Config.island.iconFade }
        }
        onOpacityChanged: {
            if (opacity === 0 && !slot.shown)
                slot.occupying = false;
        }
    }
}
