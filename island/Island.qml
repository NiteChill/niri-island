import QtQuick
import QtQuick.Shapes
import QtQuick.Window

import "../services"

// A surface that springs to the size of its active mode and hosts every one of its modes at once (see
// IslandMode for the content transition). Two of them exist (shell.qml):
//  - the notch: what happens now (volume, alerts, the music playing, the media controls) in the black
//    island at the top of the screen, glued to its edge with concave "flares" (island.style "notch") or
//    floating (style "pill"); at rest a small empty shape (RestMode)
//  - the dropdown surface: the dropdowns opened from the bar (Wi-Fi, battery, the calendar...), a card
//    under the bar in the light / dark theme's color, hidden while none is open (Dropdown.qml)
// The shape is drawn as a path: Apple-style continuous corners (island.cornerSmoothing; 0 = a plain rounded
// rectangle instead, cheaper), its corners from corners.* (Config.corner).
// Colors: it sets the palette its content inherits (palette.window = its fill, windowText / placeholderText
// = text / secondary): white on black in the notch, the theme's in the dropdowns.
Item {
    id: island

    // ---- API ----
    property string current: ""          // name of the mode to show (each mode compares itself to it)
    // height a mode takes at least (one-line pop-ups: island.activityHeight); the notch's own resting
    // size is RestMode's
    property real restHeight: Config.restHeight
    property real restWidth: 0
    property real minWidth: 0
    // the screen's size (set by shell.qml), for modes that follow its proportions
    property real screenWidth: 0
    property real screenHeight: 0
    property var transition: Config.island.transition   // read by IslandMode as `tr`
    default property alias modes: host.data
    readonly property bool hovered: hover.hovered
    // the open dropdown was opened from the keyboard (set by shell.qml): e.g. quick settings selects its
    // first switch right away
    property bool keyboardOpened: false
    // glued to the top edge with flares (the notch); false = rounded all round
    property bool attached: false
    // the corner role of its corners (Config.corner): "island" for the notch, "menu" for the dropdowns
    property string cornerRole: "island"
    property color fill: Config.island.color
    // a hairline around the shape (the dropdown card, like a macOS menu's edge); 0 = none
    property color edgeColor: "transparent"
    property real edgeWidth: 0
    property color textColor: Config.colors.text
    property color secondaryColor: Config.colors.secondary
    // with no active mode: keep the last size (the dropdown surface fading out) instead of springing to rest
    property bool keepSize: false
    // the content only crossfades while the shape morphs (the dropdowns): no scaling with the shape, no pop,
    // no blur. False = the notch's full transition (see IslandMode)
    property bool plainFade: false
    // forwarded from the modes, so the owner handles them once for all modes
    signal requestState(string name)
    signal holdKeyboard()

    palette.window: fill
    palette.windowText: textColor
    palette.placeholderText: secondaryColor

    // Every mode, captured once at startup: host.children itself changes when a mode's blur layer
    // is created, so reading it in a binding loops.
    property var modeList: []
    // another surface's modes the launcher also lists (the dropdowns' launcher lists the notch's media
    // controls too; set by shell.qml)
    property var extraModes: []
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
    property real _keptW: 0
    property real _keptH: 0
    readonly property real targetWidth: activeMode ? activeMode.fullWidth : keepSize ? _keptW : restWidth
    readonly property real targetHeight: activeMode ? activeMode.fullHeight : keepSize ? _keptH : restHeight

    // The only animated values. They follow _w/_h, which are only updated *after* the direction
    // flags below, so each Behavior starts with the right spring and delay.
    property real _w: 0
    property real _h: 0
    property bool _ready: false
    width: _w
    height: _h
    Component.onCompleted: {
        // modes sit in the host directly or one level down (modes/AllModes.qml, modes/AllDropdowns.qml)
        let list = [];
        const add = items => {
            for (let i = 0; i < items.length; i++) {
                const m = items[i];
                if (m.leaveVisibility === undefined) {
                    if (m.isModeList !== undefined)
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
    // while true, size changes jump instead of springing (the dropdown surface appearing from nothing)
    property bool jumping: false
    // jump to the active mode's size without springing
    property bool _jumping: false
    function jumpToTarget() {
        _jumping = true;
        _w = targetWidth;
        _h = targetHeight;
        _jumping = false;
    }

    // ---- shape ----
    // concave corners joining the island to the screen edge (attached only), never taller than half the island
    readonly property real flare: attached ? Config.corner("flare", height) : 0
    // the active mode may round the island's corners more or less than the style (IslandMode.cornerScale);
    // the island eases between the two over island.cornerMorph, so it never snaps
    property real cornerScale: activeMode ? activeMode.cornerScale : 1
    Behavior on cornerScale {
        NumberAnimation {
            duration: Config.island.cornerMorph
            easing.type: Easing.OutCubic
        }
    }
    // corner radii now (the corner style's, at most half the height)
    readonly property real corner: Math.min(Config.corner(cornerRole, height) * cornerScale, height / 2)
    readonly property real attachedCorner: Math.min(Config.corner("attached", height) * cornerScale, height / 2)
    // no smoothing and not attached: a plain rounded rectangle, cheaper to draw than the path (it isn't
    // rebuilt on every frame of a spring)
    readonly property bool plain: Config.island.cornerSmoothing <= 0 && !attached
    // Edges on whole device pixels: at a 1.25 scale a 3 px gap is 3.75 pixels and a 38 px island 47.5, so
    // its edges fell mid-pixel and showed as a faint row above and below (clear with small corners). The
    // shape is drawn with each edge moved to the nearest pixel, both inward, so the content stays centred
    // in it. Layout and the transitions keep the exact size.
    // (The window's own ratio: Screen.devicePixelRatio says 2 there.)
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

    Rectangle {
        x: island.drawnX
        y: island.drawnY
        width: island.drawnWidth
        height: island.drawnHeight
        visible: island.plain
        radius: Math.min(island.corner, Math.min(width, height) / 2)
        color: island.fill
        border.width: island.edgeWidth
        border.color: island.edgeColor
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
            strokeColor: island.edgeWidth > 0 ? island.edgeColor : "transparent"
            strokeWidth: island.edgeWidth > 0 ? island.edgeWidth : -1
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
    // (a size that isn't a number, a setting missing for a moment during a live reload, is ignored: a
    // spring toward NaN never settles, and the shell spun at 100 % CPU, frozen, on 2026-11-23)
    onTargetWidthChanged: {
        if (!isFinite(targetWidth))
            return;
        if (activeMode)
            _keptW = targetWidth;
        if (!_ready)
            return;
        holdW = switching();
        shrinkingW = targetWidth < width;   // vs the current size: targets can change twice in a row
        _w = targetWidth;
    }
    onTargetHeightChanged: {
        if (!isFinite(targetHeight))
            return;
        if (activeMode)
            _keptH = targetHeight;
        if (!_ready)
            return;
        holdH = switching();
        shrinkingH = targetHeight < height;
        _h = targetHeight;
    }
    readonly property var motionW: Config.spring(shrinkingW ? Config.island.shrink : Config.island.expand)
    readonly property var motionH: Config.spring(shrinkingH ? Config.island.shrink : Config.island.expand)

    Behavior on _w {
        enabled: island._ready && !island._jumping && !island.jumping
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
        enabled: island._ready && !island._jumping && !island.jumping
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
