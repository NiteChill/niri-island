import QtQuick
import QtQuick.Effects

import "../services"

// Base for every island mode. Owns the wiring (active state, requestState, keyboard focus, Escape)
// and the transition, so a new mode only declares its size and content. Transition:
//  - the mode is laid out at its full size and scaled to fit the island's *current* (animated)
//    size, so its content grows and shrinks with the shape instead of floating in an empty blob
//  - outgoing content fades + blurs out quickly while it shrinks with the island
//  - incoming content waits for the leaving one (handoff) and for the island to have grown enough,
//    then fades in over tr.fadeIn ms: opacity first (tr.fadeInOpacity of the way), blur clears last
//  - opening modes get a springy scale "pop" on top, so the content bounces at you
//  - followIsland: once settled, the content is laid out at the island's live width (edges slide with it)
//  - incoming content is never scaled below tr.minScale while the island grows (it's clipped instead): the
//    island's growth is mapped onto minScale -> 1, so the content moves from the first frame
// Tunables: config.jsonc island.transition (a mode can override some: trOverride)
Item {
    id: mode

    // state name (e.g. "battery"); the mode is active while the island's `current` is this name
    property string name: ""
    readonly property bool active: island ? island.current === name : false
    // ask to switch the island to another mode ("idle" closes)
    signal requestState(string name)
    // emitted right before a key press switches/closes the mode (Escape, Enter in search): shell.qml then
    // keeps the keyboard until that key is released, so it never leaks to the window below
    signal holdKeyboard()
    // close after collapseDelay once the mouse leaves (false: stays until Escape / an action, e.g. search)
    property bool autoClose: true
    // the island's corners while this mode is active: the corner style's times this (1 = as they are;
    // the screenshot rounds them more); Island eases to it over island.cornerMorph
    property real cornerScale: 1
    // the island may be smaller than island.minWidth / the resting height for this mode (calm's pill)
    property bool belowMinimum: false

    // ---- keyboard ----
    // item that gets keyboard focus while this mode is open (null = the mode doesn't use the keyboard).
    // The window only actually has the keyboard if shell.qml grants it (see keyboardFocus there).
    property Item keyTarget: null
    function grabKeys() {
        if (active && visible && keyTarget)
            keyTarget.forceActiveFocus();
    }
    onVisibleChanged: grabKeys()     // a hidden item can't hold focus, so retry once it shows
    // close from a key press: hold the keyboard until the key is released, then go back to idle
    function close() {
        holdKeyboard();
        requestState("idle");
    }
    // Escape closes the mode, unless the mode is busy with something Escape should cancel first
    // (e.g. the Wi-Fi password field): then escapeCloses is false and `escaped` fires instead
    property bool escapeCloses: true
    signal escaped()
    Keys.onEscapePressed: {
        if (escapeCloses)
            close();
        else
            escaped();
    }
    // how the mode appears in the search launcher: { title, subtitle, keywords, icon } from its config
    // section (e.g. Config.battery.launcher). null = not listed.
    property var launcher: null

    // Island > host Item > AllModes > mode: the nearest ancestor that is an Island (has modeList)
    readonly property Item island: {
        let p = parent;
        while (p && p.modeList === undefined)
            p = p.parent;
        return p;
    }
    // transition settings: the island's own (config.jsonc island.transition),
    // optionally overridden per mode (e.g. BatteryMode sets trOverride: Config.battery.transition)
    property var trOverride: ({})
    readonly property var tr: Object.assign({}, island ? island.transition : Config.island.transition, trOverride || {})

    // the size the island takes when this mode is active (mirrors IslandShape.targetWidth/Height)
    readonly property real fullWidth: belowMinimum ? implicitWidth : Math.max(island ? island.minWidth : 0, implicitWidth)
    readonly property real fullHeight: belowMinimum ? implicitHeight : Math.max(island ? island.restHeight : 0, implicitHeight)

    // how close the island is to this mode's size: 1 = exactly there, ->0 = far off (either way).
    // Only needed while active (canAppear): an inactive mode returns before reading the island's size, so
    // it isn't re-evaluated on every frame of the island's spring (15 modes x 60 fps).
    readonly property real progress: {
        if (!active || !island || island.width <= 0 || island.height <= 0)
            return 1;
        const rw = island.width / fullWidth, rh = island.height / fullHeight;
        return Math.min(Math.min(rw, 1 / rw), Math.min(rh, 1 / rh));
    }

    // 1 while active, fades to 0 over tr.fadeOut ms once deactivated (instant on activation).
    // Fast start (OutCubic): the old content reacts on the first frame and is mostly gone while the island
    // is still contracting, like the Dynamic Island collapse.
    // Driven imperatively from onActiveChanged (not a Behavior with a duration binding: Qt doesn't
    // guarantee the duration updates before the animation starts, which made the fade instant).
    property real presence: active ? 1 : 0
    NumberAnimation {
        id: presenceOut
        target: mode
        property: "presence"
        to: 0
        duration: mode.tr.fadeOut
        // OutCubic: reacts on the first frame (Apple-style: closing never hesitates), then eases out.
        // An ease-in here (slow start) made closing feel laggy: nothing visibly moved for ~100 ms.
        easing.type: Easing.OutCubic
    }

    // 0 while active, runs 0 -> 1 over tr.fadeOut ms once deactivated: drives the outgoing scale-down
    property real leave: active ? 0 : 1
    NumberAnimation {
        id: leaveOut
        target: mode
        property: "leave"
        to: 1
        duration: mode.tr.fadeOut
        easing.type: Easing.OutCubic
    }

    // what this mode contributes while leaving (only time-based, so the island can read it without loops)
    readonly property real leaveVisibility: active ? 0 : presence
    // on screen: active, or still fading out. A leaving mode must not change while it animates out (a list
    // collapsing, a highlight jumping, the seconds switching off read as jitter): modes freeze what they
    // show when `active` goes false, and switch things off / reset only once `onScreen` goes false too.
    readonly property bool onScreen: active || presence > 0

    // ---- incoming ----
    // appear: 0 -> 1 over tr.fadeIn ms, started once the leaving mode is below tr.handoff opacity
    // and the island is at least tr.fadeInStart of the way to this mode's size.
    property real appear: active ? 1 : 0
    property bool appearStarted: true
    // false until the switch has settled (set from Qt.callLater in onActiveChanged): the leaving mode's own
    // onActiveChanged may run after ours, so at activation leavingVisibility can still read 0 and the
    // incoming mode would skip the handoff. Qt picks that order, so without this one direction of a switch
    // crossfaded and the other waited (volume <-> brightness looked different each way).
    property bool appearArmed: true
    property bool opening: false
    NumberAnimation {
        id: appearIn
        target: mode
        property: "appear"
        to: 1
        duration: mode.tr.fadeIn
        easing.type: Easing.OutQuad
        // once opened, stop scaling with the island: later resizes (e.g. search results changing)
        // just reveal / clip the content instead of shrinking it
        onFinished: settleIn.start()
    }

    // once settled, lay the content out at the island's live width instead of the mode's target width,
    // so things anchored to the edges slide with the island when the mode resizes itself (idle icons)
    property bool followIsland: false

    // 1 = content scaled to fit the island (opening), 0 = natural size (settled)
    property real fitWeight: 1
    NumberAnimation {
        id: settleIn
        target: mode
        property: "fitWeight"
        to: 0
        duration: Config.motion.settleDuration
        easing.type: Easing.OutCubic
    }
    readonly property bool canAppear: active && (!island || island.leavingVisibility <= tr.handoff) && progress >= tr.fadeInStart
    onCanAppearChanged: tryAppear()
    function tryAppear() {
        if (appearStarted || !appearArmed || !canAppear)
            return;
        appearStarted = true;
        appearIn.start();
        // bouncy pop starts with the content, not before it's visible
        if (opening) {
            popBehavior.enabled = false;
            pop = tr.pop.from;
            popBehavior.enabled = true;
            pop = 1;
        }
    }
    function armAppear() {
        appearArmed = true;
        tryAppear();
    }
    // last visibility while active, so a mode switched away mid-appear doesn't flash to full
    property real shownVisibility: 1
    onVisibilityChanged: {
        if (active)
            shownVisibility = visibility;
    }
    // The content is on screen now (tr.contentStart of the way through its fade-in): a mode's own entrance
    // animation (the mic's wiggle, the charging fill, the Wi-Fi bars...) starts here, not on activeChanged.
    // At activation the content is still invisible (it waits for the leaving mode, then fades in), so an
    // animation started there played mostly unseen. `hasAppeared`: true from then until deactivated.
    signal appeared()
    property bool hasAppeared: false
    // armed in onActiveChanged (not from the `appear` binding, which jumps to 1 on a first activation)
    property bool _waitAppear: false
    onAppearChanged: {
        if (_waitAppear && active && appear >= tr.contentStart) {
            _waitAppear = false;
            hasAppeared = true;
            appeared();
        }
    }
    // opacity level: incoming reaches full opacity fadeInOpacity of the way through, outgoing = presence
    readonly property real visibility: active ? Math.min(1, appear / tr.fadeInOpacity) : presence

    // Bouncy pop on open: jumps to tr.pop.from, then springs (underdamped) back to 1.
    // Only for modes that are bigger than the island when they activate (i.e. opening); started with appear.
    property real pop: 1
    readonly property var popSpring: Config.spring(tr.pop)
    Behavior on pop {
        id: popBehavior
        SpringAnimation {
            spring: mode.popSpring.spring
            damping: mode.popSpring.damping
            epsilon: 0.001
        }
    }
    onActiveChanged: {
        grabKeys();
        presenceOut.stop();
        leaveOut.stop();
        appearIn.stop();
        settleIn.stop();
        fitWeight = 1;
        hasAppeared = false;
        _waitAppear = active;
        if (active) {
            presence = 1;
            leave = 0;
            appear = 0;
            opening = !!island && island.height < fullHeight;
            appearStarted = false;
            appearArmed = false;
            // deferred: the leaving mode may not have registered itself as leaving yet at this point
            Qt.callLater(armAppear);
        } else {
            presence = shownVisibility;   // fade out from however visible it actually was
            leave = 0;
            presenceOut.start();
            leaveOut.start();
        }
    }

    // laid out at full size, pinned top-centre, scaled to fit inside the animated island
    width: followIsland && active && island ? fitWeight * fullWidth + (1 - fitWeight) * island.width : fullWidth
    height: fullHeight
    // hidden modes (not active, faded out) skip the island's size here and in `scale`: same reason as
    // `progress`. Measured: -17 % main-thread CPU while switching modes.
    x: island && (active || presence > 0) ? (island.width - width) / 2 : 0
    y: 0
    transformOrigin: Item.Top
    scale: {
        if (!island || !active && presence <= 0)
            return 1;
        const fit = Math.max(0, Math.min(tr.maxScale, Math.min(island.width / fullWidth, island.height / fullHeight)));
        if (active) {
            // incoming content never looks smaller than tr.minScale (the island clips the overflow). The
            // island's growth is mapped onto minScale -> 1 rather than clamped (max(fit, minScale)): a clamp
            // holds the content still until the island is minScale grown, then it suddenly follows (a
            // visible pause mid-opening, measured on quick settings)
            const inFit = fit < 1 ? tr.minScale + (1 - tr.minScale) * fit : fit;
            return (fitWeight * inFit + (1 - fitWeight)) * pop;
        }
        // outgoing: follow the island more loosely (outFit < 1) so it stays readable, plus its own
        // time-based shrink to outScale; anything that overflows is clipped by the island
        return Math.pow(fit, tr.outFit) * (1 - (1 - tr.outScale) * leave);
    }

    opacity: visibility
    visible: opacity > 0.001

    // blur while transitioning; the layer only exists mid-transition to keep idle cost at zero.
    // incoming: clears over the whole fade-in (so it's still visible after opacity is full).
    readonly property real blurAmount: (active ? 1 - appear : Math.pow(1 - presence, tr.blurOutCurve)) * tr.blur
    layer.enabled: blurAmount > 0.01
    layer.effect: MultiEffect {
        blurEnabled: true
        blur: mode.blurAmount
        blurMax: mode.tr.blurMax
    }
}
