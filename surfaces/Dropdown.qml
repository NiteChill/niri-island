import QtQuick

import "../services"
import "../island"
import "../modes"
import "../widgets"

// The dropdowns' surface: one card under the bar (panel.gap below it) in the light / dark theme
// (Config.theme), holding every dropdown (modes/AllDropdowns.qml) with the island's engine: switching
// from one dropdown to another springs the card to the new size and slides it under the new icon, the
// contents crossfading (IslandMode). Each hangs centred under the bar item it comes from (Bar.anchorFor),
// kept panel.margin inside the screen; the others (search, wallpaper, screenshots) under the notch.
// Opening from nothing: the card appears at its size and place (no spring from the last one) and fades in;
// closing fades it out where it is. Between dropdowns the card morphs (size and place) and the contents
// only crossfade (Island.plainFade). Frosted (panel.blur, 2026-11-25): see-through, niri blurring behind it (Frost).
Item {
    id: drop

    // ---- in (shell.qml) ----
    property var bar: null
    property real screenWidth: 0
    property real screenHeight: 0
    property bool keyboardOpened: false
    property var extraModes: []
    signal requestState(string name)
    signal holdKeyboard()

    readonly property alias surface: surface
    readonly property string name: Activity.dropdown
    readonly property bool shown: name !== ""
    // where it hangs: the middle of the bar item, else the middle of the screen
    function anchorOf(n) {
        const a = bar && n !== "" ? bar.anchorFor(n) : -1;
        return a >= 0 ? a : screenWidth / 2;
    }
    readonly property real wantedAnchor: anchorOf(name)

    // ---- appearing / leaving ----
    property real presence: 0
    NumberAnimation {
        id: fade
        target: drop
        property: "presence"
        easing.type: Easing.OutCubic
    }
    property real anchorX: screenWidth / 2
    Behavior on anchorX {
        enabled: !surface.instant
        SpringAnimation {
            spring: Config.spring(Config.island.expand).spring
            damping: Config.spring(Config.island.expand).damping
            epsilon: 0.5
        }
    }
    // closing keeps the card where it is (the anchor of "" is the screen's middle: it slid there as it faded)
    onWantedAnchorChanged: {
        if (name !== "")
            anchorX = wantedAnchor;
    }
    // (from `name` itself: `shown` may not have caught up yet inside this handler)
    onNameChanged: {
        const open = name !== "";
        const fresh = open && presence <= 0.001;
        if (fresh) {
            // from nothing: straight to its size and place
            surface.instant = true;
            surface.current = name;
            anchorX = anchorOf(name);
            Qt.callLater(() => surface.instant = false);
        } else
            surface.current = name;
        fade.stop();
        fade.to = open ? 1 : 0;
        fade.duration = open ? Config.panel.appear.fadeIn : Config.panel.appear.fadeOut;
        fade.start();
    }

    // the card's place, kept inside the screen
    readonly property real surfaceX: Math.max(Config.panel.margin, Math.min(screenWidth - Config.panel.margin - surface.width, anchorX - surface.width / 2))

    // the area that takes the pointer (none while hidden)
    readonly property rect inputRect: presence > 0 ? Qt.rect(surface.x, surface.y, surface.width, surface.height) : Qt.rect(0, 0, 0, 0)

    // frosted glass (panel.blur): the card is see-through and niri blurs what's behind it (Frost)
    readonly property color cardFill: Config.frosted(Config.theme.surface)
    Frost {
        x: surface.x
        y: surface.y
        width: surface.width
        height: surface.height
        radius: Config.corner("menu", surface.height)
        // (read by Frost: the blur goes once the card is mostly faded, panel.blur.showAbove)
        opacity: drop.presence
    }

    Island {
        id: surface
        property bool instant: false
        current: ""
        x: drop.surfaceX
        attached: false
        cornerRole: "menu"
        restHeight: 0
        minWidth: 0
        keepSize: true
        fill: drop.cardFill
        edgeColor: Qt.alpha(Config.theme.border, Config.panel.edgeOpacity)
        edgeWidth: Config.panel.edgeWidth
        textColor: Config.theme.text
        secondaryColor: Config.theme.secondary
        keyboardOpened: drop.keyboardOpened
        screenWidth: drop.screenWidth
        screenHeight: drop.screenHeight
        extraModes: drop.extraModes
        jumping: instant
        opacity: drop.presence
        visible: drop.presence > 0
        plainFade: true

        onRequestState: name => drop.requestState(name)
        onHoldKeyboard: drop.holdKeyboard()

        AllDropdowns {}
    }
}
