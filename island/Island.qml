import QtQuick
import QtQuick.Shapes
import QtQuick.Window

import "../services"

// The island: one rounded shape at the top of the screen that springs to the size of its active mode,
// and hosts every mode at once (see IslandMode for the content transition). It shows panels the user
// opens (search, battery, wifi) and what Activity puts up (volume, brightness, microphone, messages,
// notifications); shell.qml picks the mode from Activity.current. Settings: config.jsonc "island".
// The shape is drawn as a path: Apple-style continuous corners (island.cornerSmoothing; 0 = a plain rounded
// rectangle instead, cheaper), corners from the corner style (island.shape, see Config.corner), and optionally
// glued to the top edge of the screen with concave "flares" joining it to the edge (island.attachToTop,
// NotchNook style). The flares are drawn outside the island's bounds (not clickable, not part of its size).
Item {
    id: island

    // ---- API ----
    property string current: "idle"      // name of the mode to show (each mode compares itself to it)
    // height when the active mode is shorter (idle): the bar minus its gaps (attached: no gap above)
    readonly property real restHeight: Config.restHeight
    // space above the island inside the bar (0 when attached to the top edge)
    readonly property real topGap: attached ? 0 : Config.bar.gaps
    // the screen's size (set by shell.qml), for modes that follow its proportions
    property real screenWidth: 0
    property real screenHeight: 0
    readonly property real restWidth: Config.island.minWidth
    readonly property real minWidth: Config.island.minWidth
    readonly property var transition: Config.island.transition   // read by IslandMode as `tr`
    default property alias modes: host.data
    readonly property bool hovered: hover.hovered
    // the open panel was opened from the keyboard (set by shell.qml): e.g. quick settings selects its first
    // switch right away
    property bool keyboardOpened: false
    // forwarded from the modes, so the owner handles them once for all modes
    signal requestState(string name)
    signal holdKeyboard()

    // Every mode, captured once at startup: host.children itself changes when a mode's blur layer
    // is created, so reading it in a binding loops.
    property var modeList: []
    readonly property Item activeMode: modeList.find(m => m.active) || null

    // How visible the most visible *leaving* mode still is (0 = nothing leaving).
    // Incoming modes wait on this so the two don't pile on top of each other.
    readonly property real leavingVisibility: {
        let v = 0;
        for (let i = 0; i < modeList.length; i++)
            v = Math.max(v, modeList[i].leaveVisibility);
        return v;
    }

    // Targets: pure bindings, never animated
    readonly property real targetWidth: activeMode ? activeMode.fullWidth : restWidth
    readonly property real targetHeight: activeMode ? activeMode.fullHeight : restHeight

    // The only animated values. They follow _w/_h, which are only updated *after* the direction
    // flags below, so each Behavior starts with the right spring and delay.
    property real _w: 0
    property real _h: 0
    property bool _ready: false
    width: _w
    height: _h
    Component.onCompleted: {
        // modes sit in the host directly or one level down (modes/AllModes.qml)
        let list = [];
        const add = items => {
            for (let i = 0; i < items.length; i++) {
                const m = items[i];
                if (m.leaveVisibility === undefined) {
                    if (m.panels !== undefined)
                        add(m.children);
                    continue;
                }
                m.requestState.connect(island.requestState);
                m.holdKeyboard.connect(island.holdKeyboard);
                list.push(m);
            }
        };
        add(host.children);
        modeList = list;
        _w = targetWidth;
        _h = targetHeight;
        _lastMode = activeMode;
        _ready = true;
    }

    // ---- shape ----
    readonly property bool attached: Config.island.attachToTop
    // concave corners joining the island to the screen edge (attached only), never taller than half the island
    readonly property real flare: attached ? Config.corner("flare", height) : 0
    // the active mode may round the island's corners more or less than the style (IslandMode.cornerScale:
    // the screenshot's 1.5); the island eases between the two over island.cornerMorph, so it never snaps
    property real cornerScale: activeMode ? activeMode.cornerScale : 1
    Behavior on cornerScale {
        NumberAnimation {
            duration: Config.island.cornerMorph
            easing.type: Easing.OutCubic
        }
    }
    // corner radii now (the corner style's, at most half the height)
    readonly property real corner: Math.min(Config.corner("island", height) * cornerScale, height / 2)
    readonly property real attachedCorner: Config.corner("attached", height)
    // no smoothing and not attached: a plain rounded rectangle, cheaper to draw than the path (it isn't
    // rebuilt on every frame of a spring)
    readonly property bool plain: Config.island.cornerSmoothing <= 0 && !attached
    // see-through when blurred, so the blur shows (island.blurOpacity)
    readonly property color fill: Config.island.blur ? Qt.alpha(Config.island.color, Config.island.blurOpacity) : Config.island.color
    // Edges on whole device pixels: at a 1.25 scale the 3 px gap is 3.75 pixels and the 38 px island
    // 47.5, so its edges fell mid-pixel and showed as a faint row above and below (clear with small
    // corners). The shape is drawn with each edge moved to the nearest pixel (3.75 -> 4, 51.25 -> 51: both
    // inward, so the content stays centred in it). Layout and the transitions keep the exact size.
    // (The window's own ratio: Screen.devicePixelRatio says 2 there. The island sits in the window's
    // content item, at the window's origin.)
    readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
    function snap(v) {
        return Math.round(v * dpr) / dpr;
    }
    readonly property real drawnX: snap(x) - x
    readonly property real drawnY: snap(y) - y
    readonly property real drawnWidth: snap(x + width) - snap(x)
    readonly property real drawnHeight: snap(y + height) - snap(y)

    readonly property string shapePath: {
        const w = drawnWidth, h = drawnHeight, s = Config.island.cornerSmoothing;
        if (w <= 0 || h <= 0 || plain)
            return "";
        const n = v => v.toFixed(2);
        if (!attached)
            return Config.roundedRectPath(w, h, corner, s);
        // attached: flat top running into the screen edge, flares at the top, rounded bottom corners
        const f = flare;
        const q = Config.cornerParams(attachedCorner, s, Math.min(w / 2, h - f));
        const fa = " A " + n(f) + " " + n(f) + " 0 0 0 ";
        return "M " + n(-f) + " 0 H " + n(w + f) + fa + n(w) + " " + n(f)
            + " V " + n(h - q.p) + Config.cornerSvg(q, 1)
            + " H " + n(q.p) + Config.cornerSvg(q, 2)
            + " V " + n(f) + fa + n(-f) + " 0 Z";
    }
    // Blur behind the island (island.blur): shell.qml asks the compositor to blur what's under a rounded
    // rectangle the island's size, with plain round corners of the island's radius (as clamped by
    // cornerParams). The smoothed outline matches it at the diagonal and runs at most 0.5 px inside it
    // near the edges (measured at radius 40, smoothing 0.6), so no blur shows past the outline.
    // Attached: square top (the flares aren't blurred).
    // (0 while blur is off: not recomputed on every frame of the spring for nothing)
    readonly property real blurCorner: !Config.island.blur ? 0 : attached
        ? Config.cornerParams(attachedCorner, Config.island.cornerSmoothing, Math.min(width / 2, height - flare)).r
        : Config.cornerParams(corner, Config.island.cornerSmoothing, Math.min(width, height) / 2).r

    Rectangle {
        x: island.drawnX
        y: island.drawnY
        width: island.drawnWidth
        height: island.drawnHeight
        visible: island.plain
        radius: Math.min(island.corner, Math.min(width, height) / 2)
        color: island.fill
    }
    Shape {
        x: island.drawnX
        y: island.drawnY
        width: island.drawnWidth
        height: island.drawnHeight
        visible: !island.plain
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: island.fill
            strokeColor: "transparent"
            PathSvg {
                path: island.shapePath
            }
        }
    }

    // animation
    // Growing and shrinking use different springs (island.expand / island.shrink), the same for both axes.
    // Direction is decided once per target change (per axis) so the spring doesn't swap mid-flight.
    property bool shrinkingW: false
    property bool shrinkingH: false
    // the shrink hold (shrinkDelay) is only for switching modes, not for a mode resizing itself
    // (e.g. search results changing). Set before _w/_h so the Behaviors read it.
    property bool holdW: false
    property bool holdH: false
    property Item _lastMode: null
    property double _switchTime: 0
    // true right after a mode switch (targets can change more than once during one switch)
    function switching() {
        if (activeMode !== _lastMode) {
            _lastMode = activeMode;
            _switchTime = Date.now();
        }
        return Date.now() - _switchTime < Config.island.switchWindow;
    }
    onTargetWidthChanged: {
        if (!_ready)
            return;
        holdW = switching();
        shrinkingW = targetWidth < width;   // vs the current size: targets can change twice in a row
        _w = targetWidth;
    }
    onTargetHeightChanged: {
        if (!_ready)
            return;
        holdH = switching();
        shrinkingH = targetHeight < height;
        _h = targetHeight;
    }
    readonly property var motionW: Config.spring(shrinkingW ? Config.island.shrink : Config.island.expand)
    readonly property var motionH: Config.spring(shrinkingH ? Config.island.shrink : Config.island.expand)

    Behavior on _w {
        enabled: island._ready
        SequentialAnimation {
            // closing: hold the shape briefly so the content visibly scales down first
            PauseAnimation {
                duration: island.shrinkingW && island.holdW ? Config.island.shrinkDelay : 0
            }
            SpringAnimation {
                spring: island.motionW.spring
                damping: island.motionW.damping
                epsilon: 0.5
            }
        }
    }
    Behavior on _h {
        enabled: island._ready
        SequentialAnimation {
            // closing: hold the shape briefly so the content visibly scales down first
            PauseAnimation {
                duration: island.shrinkingH && island.holdH ? Config.island.shrinkDelay : 0
            }
            SpringAnimation {
                spring: island.motionH.spring
                damping: island.motionH.damping
                epsilon: 0.5
            }
        }
    }

    // content
    Item {
        id: host
        anchors.fill: parent
        clip: true
    }

    HoverHandler {
        id: hover
    }
}
