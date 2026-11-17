import QtQuick

import "../services"

// The motion of a panel's big symbol (the Wi-Fi fan, the Bluetooth rune), shared so both panels move
// alike. No visuals: the panel draws its symbol in `parts` pieces and colors part p with partColor(p).
//  - light-up: each part fades from grey to the accent, one after the other (panel.sweep.stagger apart);
//    replay(true) when the panel opens (after panel.sweep.delay, once the content has faded in), replay(false)
//    when something connects while it's open. When the lit parts drop to none (turned off, disconnected),
//    the last lit ones stay (`fading`) while the light-up runs back, so they go out instead of vanishing.
//    Only the color moves: shrinking a round-capped stroke stalls as a dot and then pops
//  - ripple: while `rippling` (searching, connecting), a glow runs through the parts, faster when `fast`
//  - fail(): the symbol shakes sideways (read `shake`) and flashes red (panel.shake)
// Colors are opaque (grey and the accent blended over the island color): strokes that overlap don't
// double up into bright spots.
Item {
    id: motion

    // ---- in ----
    property bool active: false        // the panel is open
    property int parts: 1
    property int live: 0               // parts lit right now (0 = none)
    property bool rippling: false
    property bool fast: false          // connecting: the faster ripple
    property bool hovered: false       // the symbol is under the pointer (it's a switch): a little brighter

    // ---- out ----
    // parts lit, including the ones going out
    readonly property int lit: live > 0 ? live : fading
    property real shake: 0
    property bool flashing: false

    readonly property var cfg: Config.panel

    // ---- light-up ----
    property int lastLive: 0
    property int fading: 0
    onLiveChanged: {
        if (live > 0) {
            const was = lastLive;
            lastLive = live;
            if (was === 0 && fading === 0 && active && !lightDelay.running)
                replay(false);
            return;
        }
        if (!active || lastLive === 0)
            return;
        fading = lastLive;
        lastLive = 0;
        lightIn.stop();
        lightOut.restart();
    }
    // 0 -> 1 lights the parts in order; back to 0 puts them out in reverse
    property real lightUp: 1
    NumberAnimation {
        id: lightIn
        target: motion
        property: "lightUp"
        from: 0
        to: 1
        duration: motion.cfg.sweep.duration
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: lightOut
        target: motion
        property: "lightUp"
        to: 0
        duration: motion.cfg.sweep.duration
        easing.type: Easing.OutCubic
        onFinished: {
            motion.fading = 0;
            motion.lightUp = 1;
        }
    }
    Timer {
        id: lightDelay
        interval: motion.cfg.sweep.delay
        onTriggered: lightIn.start()
    }
    function replay(delayed) {
        lightOut.stop();
        fading = 0;
        lastLive = live;
        lightIn.stop();
        lightDelay.stop();
        lightUp = 0;
        if (delayed)
            lightDelay.start();
        else
            lightIn.start();
    }
    // how lit part p is, 0 - 1
    function light(p) {
        const st = cfg.sweep.stagger;
        const span = 1 - (parts - 1) * st;
        return Math.max(0, Math.min(1, (lightUp - p * st) / span));
    }

    // ---- ripple ----
    property real ripple: 0
    NumberAnimation on ripple {
        running: motion.rippling
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: motion.fast ? motion.cfg.ripple.connectingDuration : motion.cfg.ripple.duration
        onRunningChanged: if (!running)
            motion.ripple = 0
    }
    // extra brightness for part p as the ripple passes
    function rippleBoost(p) {
        if (!rippling)
            return 0;
        const at = ripple * (parts + 1) - 0.5;
        return cfg.ripple.boost * Math.max(0, 1 - Math.abs(at - p) / cfg.ripple.width);
    }

    // ---- failure: shake (like a head saying no) and flash red ----
    function fail() {
        flashing = true;
        flashTimer.restart();
        shakeAnim.restart();
    }
    Timer {
        id: flashTimer
        interval: motion.cfg.shake.flashDuration
        onTriggered: motion.flashing = false
    }
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation {
            target: motion
            property: "shake"
            to: motion.cfg.shake.distance
            duration: motion.cfg.shake.duration / 8
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: motion
            property: "shake"
            to: -motion.cfg.shake.distance
            duration: motion.cfg.shake.duration / 4
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: motion
            property: "shake"
            to: motion.cfg.shake.distance / 2
            duration: motion.cfg.shake.duration / 4
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: motion
            property: "shake"
            to: 0
            duration: motion.cfg.shake.duration * 3 / 8
            easing.type: Easing.OutQuad
        }
    }

    // ---- colors ----
    readonly property real hoverBoost: hovered ? cfg.glyph.hoverBoost : 0
    // part p, opaque: grey (the unlit opacity over the island color, brighter under the pointer and as the
    // ripple passes) blended towards the accent as it lights up; all red while the failure flash shows
    function partColor(p) {
        const boost = rippleBoost(p) + hoverBoost;
        const grey = Qt.tint(Config.island.color, Qt.alpha(Config.colors.text, cfg.glyph.trackOpacity + boost));
        const lit = Qt.tint(flashing ? Config.colors.danger : Config.colors.accent, Qt.alpha(Config.colors.text, boost));
        const amount = flashing ? 1 : p < motion.lit ? light(p) : 0;
        return Qt.tint(grey, Qt.alpha(lit, amount));
    }
}
