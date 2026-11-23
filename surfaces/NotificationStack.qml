pragma ComponentBehavior: Bound

import QtQuick

import "../services"
import "../widgets"

// The notifications (Inbox), as cards in the light / dark theme, the macOS way:
//  - banners, at the top right under the bar (shell.qml places the stack there): a new one slides in
//    from the screen's right edge, newest on top; the others make room, springing down
//    (notifications.maxVisible at once). Each leaves after its time, sliding back out to the right (Inbox
//    keeps it for the center); swiping it right sends it away at once.
//  - the center (Activity.center: it comes with the calendar, a click on the clock): under the calendar's
//    card, as wide as it: a header of two chips in the cards' color ("Notifications", Clear all), then
//    every notification in two groups under small chips, NEW (since the center was last closed) and OLD;
//    it scrolls past what fits.
// Hovering the cards pauses their time (Inbox.hovered).
Item {
    id: stack

    // a header chip: the cards' color and edge, a word in it (an inline component: at the root, and it
    // can't see this file's ids)
    component Chip: Rectangle {
        property alias text: chipLabel.text
        property alias label: chipLabel
        width: chipLabel.implicitWidth + 2 * Config.notifications.center.chipPadding
        height: Config.notifications.center.headerHeight
        radius: Config.corner("pill", height)
        color: Config.theme.card
        border.width: Config.notifications.edgeWidth
        border.color: Qt.alpha(Config.theme.border, Config.notifications.edgeOpacity)
        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            font.pixelSize: Config.notifications.center.titleSize
        }
    }

    // a key that closes the center: shell.qml keeps the keyboard until it's released
    signal holdKeyboard()

    // Escape closes the center (it has the keyboard while open)
    Item {
        id: keys
        Keys.onEscapePressed: {
            stack.holdKeyboard();
            Activity.closeAll();
        }
    }
    Connections {
        target: Activity
        function onCenterChanged() {
            if (Activity.center)
                keys.forceActiveFocus();
        }
    }

    // ---- in (shell.qml) ----
    // the calendar's card, in the window: the center hangs under it
    property rect under: Qt.rect(0, 0, 0, 0)
    property real windowHeight: 0
    readonly property var layout: Config.notifications

    width: layout.width
    // as tall as the cards on screen: the hover below (which pauses their time) only feels the pointer
    // inside this item, and with no height it never did (cards vanished under the pointer)
    height: Math.max(1, banners.contentHeight)
    palette.windowText: Config.theme.text
    palette.placeholderText: Config.theme.secondary

    // the area that takes the pointer
    readonly property rect inputRect: Activity.center || centerPresence > 0 ? Qt.rect(x + centerBox.x, y + centerBox.y, centerBox.width, centerBox.height) : banners.count > 0 ? Qt.rect(x, y, width, banners.contentHeight) : Qt.rect(0, 0, 0, 0)

    Binding {
        target: Inbox
        property: "hovered"
        value: stackHover.hovered
    }
    HoverHandler {
        id: stackHover
        onHoveredChanged: Inbox.pointerMoves++
    }
    MovedHover {
        onMoved: Inbox.pointerMoves++
    }
    // Swiping a card with two fingers (NotificationCard.scrollEvent): the stack takes the scroll events and
    // sends the whole swipe to the card under the pointer when it began, wherever that card has slid to
    // since (the pointer doesn't move: a card's own handlers lost it, and its end, once it slid away).
    // In the history, scrolling up and down that isn't a card's swipe goes on to the list. A touchpad
    // counts: WheelHandler takes only mice by default. Two handlers (each takes one direction; the
    // end-of-swipe event has no movement and only reaches the vertical one).
    property var swiped: null
    property bool _routing: false
    function cardAt(pos) {
        const view = Activity.center ? list : banners;
        const p = view.mapFromItem(stack, pos.x, pos.y);
        const item = view.itemAt(p.x + view.contentX, p.y + view.contentY);
        return !item ? null : item.card !== undefined ? item.card : item;
    }
    function route(handler, event) {
        // (one event offered to both handlers, a diagonal one: used once; the flag lasts until this delivery
        // is over. Not the event object: Qt reuses it from one event to the next)
        if (_routing)
            return;
        _routing = true;
        Qt.callLater(() => stack._routing = false);
        if (!swiped || !swiped.swiping)
            swiped = cardAt(handler.point.position);
        if (!swiped || !swiped.scrollEvent) {
            swiped = null;
            event.accepted = false;
            return;
        }
        swiped.scrollEvent(event);
        if (!swiped.swiping)
            swiped = null;
    }
    WheelHandler {
        id: wheelX
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => stack.route(wheelX, event)
    }
    WheelHandler {
        id: wheelY
        orientation: Qt.Vertical
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => stack.route(wheelY, event)
    }


    // Clear all: the cards on screen slide out right one after the other (notifications.center.clearStagger),
    // the chips fade, and once the last one is out the history is emptied (no snap)
    property bool clearing: false
    function clearAll() {
        if (clearing)
            return;
        clearing = true;
        let n = 0;
        for (let i = 0; i < Inbox.model.count; i++) {
            const item = list.itemAtIndex(i);
            if (item)
                item.card.sweep(n++ * layout.center.clearStagger);
        }
        clearDone.interval = Math.max(0, n - 1) * layout.center.clearStagger + layout.leaveDuration;
        clearDone.restart();
    }
    Timer {
        id: clearDone
        onTriggered: {
            Inbox.clearAll();
            stack.clearing = false;
        }
    }

    // ---- banners ----
    ListView {
        id: banners
        width: parent.width
        height: Math.max(contentHeight, 1)
        interactive: false
        spacing: stack.layout.gap
        model: Inbox.banners
        visible: !Activity.center
        // from past the screen's right edge (the stack's right edge is notifications.margin from it)
        readonly property real outside: stack.width + stack.layout.margin + stack.layout.shadow.blur
        // (the card's own required `uid` takes the row's)
        delegate: NotificationCard {}
        add: Transition {
            SpringAnimation {
                property: "x"
                from: banners.outside
                spring: Config.spring(stack.layout.arrive).spring
                damping: Config.spring(stack.layout.arrive).damping
                epsilon: 0.5
            }
        }
        displaced: Transition {
            NumberAnimation {
                property: "y"
                duration: stack.layout.moveDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    // ---- the center ----
    property real centerPresence: Activity.center ? 1 : 0
    Behavior on centerPresence {
        NumberAnimation {
            duration: stack.layout.center.fade
            easing.type: Easing.OutCubic
        }
    }
    // where it was last shown (kept while it fades out, the card being gone already)
    property rect _under: Qt.rect(0, 0, 0, 0)
    onUnderChanged: if (under.width > 0)
        _under = under
    Item {
        id: centerBox
        width: stack._under.width > 0 ? stack._under.width : parent.width
        x: stack._under.x + stack._under.width - width - stack.x
        y: stack._under.y + stack._under.height + stack.layout.center.gapAbove - stack.y
        height: Math.min(stack.windowHeight - stack._under.y - stack._under.height - stack.layout.center.gapAbove - stack.layout.center.bottomMargin, header.height + stack.layout.gap + list.contentHeight)
        visible: stack.centerPresence > 0
        opacity: stack.centerPresence
        // it comes down from the notch
        transform: Translate {
            y: (stack.centerPresence - 1) * stack.layout.center.drop
        }

        // the header: two chips in the cards' color, the title at the left, Clear all at the right
        Item {
            id: header
            width: parent.width
            height: stack.layout.center.headerHeight
            Chip {
                text: stack.layout.center.title
                label.font.weight: Config.panel.header.titleWeight
            }
            Chip {
                id: clearChip
                visible: Inbox.count > 0
                anchors.right: parent.right
                text: stack.layout.center.clearText
                label.color: clearHover.hovered ? palette.windowText : palette.placeholderText
                HoverHandler {
                    id: clearHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: stack.clearAll()
                }
            }
        }

        // nothing yet
        StyledText {
            visible: Inbox.count === 0
            anchors.top: header.bottom
            anchors.topMargin: stack.layout.gap
            anchors.horizontalCenter: parent.horizontalCenter
            color: Config.colors.text
            style: Text.Raised
            styleColor: Qt.alpha(Config.colors.shadow, stack.layout.shadow.opacity)
            text: stack.layout.center.emptyText
        }

        ListView {
            id: list
            // the shadows and the cards' × reach past the cards: room around them inside the clip
            readonly property real room: stack.layout.center.overhang
            anchors.top: header.bottom
            anchors.topMargin: stack.layout.gap - room
            x: -room
            width: parent.width + 2 * room
            height: parent.height - header.height - stack.layout.gap + 2 * room
            leftMargin: room
            topMargin: room
            bottomMargin: room
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: stack.layout.gap
            model: Activity.center || stack.centerPresence > 0 ? Inbox.model : null
            // NEW / OLD: a chip on top of the first card of each section, drawn as part of its row (ListView's
            // section headers can't animate: the chip vanished and everything jumped up). While that card
            // leaves with others in its section, the chip stays where it is and the card folds under it;
            // the next card then takes the chip at the same spot. The section's last card folds the chip
            // away with it.
            delegate: Item {
                id: row
                required property string uid
                required property bool leaving
                required property string section
                required property int index
                width: list.width - 2 * list.room
                // (a row being taken out can briefly have a stale index: -1, or past the end)
                function sectionAt(i) {
                    const r = i >= 0 && i < Inbox.model.count ? Inbox.model.get(i) : null;
                    return r ? r.section : "";
                }
                readonly property bool headed: {
                    Inbox.revision;
                    return sectionAt(index - 1) !== section;
                }
                readonly property bool alone: {
                    Inbox.revision;
                    return sectionAt(index + 1) !== section;
                }
                readonly property real chipRoom: headed ? stack.layout.center.chipHeight + stack.layout.gap : 0
                // the chip folds with the card only when it's the section's last
                readonly property real chipShown: headed && alone ? card.fold : 1
                height: chipRoom * chipShown + card.height
                Rectangle {
                    visible: row.headed
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (row.chipShown - 1) * row.chipRoom / 2
                    width: chipText.implicitWidth + 2 * stack.layout.center.chipPadding
                    height: stack.layout.center.chipHeight
                    radius: Config.corner("pill", height)
                    color: Qt.alpha(Config.theme.card, stack.layout.center.chipOpacity)
                    // Clear all fades it (its own value, always animated: a Behavior switched on by the same
                    // change never ran, the chip vanished at once)
                    property real clearFade: stack.clearing ? 0 : 1
                    Behavior on clearFade {
                        NumberAnimation {
                            duration: stack.layout.leaveDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                    opacity: row.chipShown * clearFade
                    StyledText {
                        id: chipText
                        anchors.centerIn: parent
                        font.pixelSize: stack.layout.center.chipSize
                        font.letterSpacing: stack.layout.center.chipSpacing
                        text: row.section === "new" ? stack.layout.center.newText : stack.layout.center.oldText
                    }
                }
                property alias card: card
                NotificationCard {
                    id: card
                    y: row.chipRoom * row.chipShown
                    uid: row.uid
                    leaving: row.leaving
                    inCenter: true
                    width: parent.width
                }
            }
            // (a card leaving plays its own exit, NotificationCard.away: the list's remove transitions never
            // ran here, the cards snapped up). When it's taken out it's already folded to nothing: the rows
            // below are where they belong (a chip handed to the next row moves its card down inside the row
            // by exactly as much), so a removal moves nothing
            removeDisplaced: Transition {}
            displaced: Transition {
                NumberAnimation {
                    property: "y"
                    duration: stack.layout.moveDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
