pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

import "../services"

// One notification as a card, laid out like macOS's (the banners at the top right and the notification
// center under the clock): the theme's card color with a hairline edge (notifications.edge*) and a soft
// shadow, `menu` corners.
//  - left: the app's icon (a soft tile with a bell when it has none; red with notifications.criticalIcon
//    for an urgent one)
//  - middle: the title in bold with when it came at the far right ("now", "5m ago": notifications.age*),
//    the message in grey under it (notifications.bodyLinesCollapsed lines, all of it on hover); the app's
//    name above the title with notifications.showAppName
//  - right: its picture, when it has one (a person, a cover); a screenshot card: the pictures piled up,
//    the newest on top (screenshot.pile.*)
// Hover: the whole message, the notification's own buttons, a × at the top-left corner. Click: what the
// notification opens (Inbox.open). Swipe it right (drag, or scroll sideways): deleted, out of the history
// too. Swipe a banner up (drag, or scroll up): off the screen only, kept in the history.
Item {
    id: card

    // ---- in ----
    required property string uid
    // its row says it's leaving (a banner whose time is up, Inbox._hideBanner): it plays its exit
    required property bool leaving
    onLeavingChanged: if (leaving)
        away(false, false, 0)
    // in the center (a swipe removes it) or a banner (a swipe only takes it off the screen)
    property bool inCenter: false

    readonly property var layout: Config.notifications
    // its row in Inbox, read again whenever Inbox changes
    readonly property var row: {
        Inbox.revision;
        return Inbox.get(uid);
    }
    readonly property bool shot: !!row && row.kind === "screenshot"
    readonly property var pictures: shot ? Inbox.pile(row) : []
    readonly property bool critical: !!row && row.urgency === "critical"
    readonly property string title: !row ? "" : shot ? Config.screenshot.title : (row.summary || row.app)
    readonly property string body: !row ? "" : shot ? (pictures.length > 1 ? Config.screenshot.countText.arg(pictures.length) : "") : row.body
    readonly property string caption: !!row && layout.showAppName && !shot && row.summary !== "" ? row.app : ""
    // how long ago it came: "now", "5m ago", "2h ago", else the date (follows the clock)
    readonly property string age: {
        if (!row)
            return "";
        const minutes = Math.floor((Sys.time.getTime() - row.time) / 60000);
        if (minutes < 1)
            return layout.age.nowText;
        if (minutes < 60)
            return layout.age.minutesText.arg(minutes);
        if (minutes < 24 * 60)
            return layout.age.hoursText.arg(Math.floor(minutes / 60));
        return Sys.formatStamp(row.time, layout.age.dateFormat);
    }
    readonly property bool hasPicture: !!row && !shot && row.image !== ""
    readonly property bool hasIcon: !!row && !shot && row.icon !== ""
    readonly property var actions: {
        Inbox.revision;
        return expanded ? Inbox.actions(uid) : [];
    }
    readonly property bool expanded: layout.expandOnHover && (hover.hovered || _keepOpen)

    // ---- size: from the parts (not a positioner, see CLAUDE.md) ----
    readonly property real pileHeight: Config.screenshot.pile.height
    readonly property real pileRatio: row && row.width > 0 && row.height > 0 ? Math.max(Config.screenshot.pile.minRatio, Math.min(Config.screenshot.pile.maxRatio, row.width / row.height)) : Config.screenshot.pile.maxRatio
    readonly property real pileWidth: pileHeight * pileRatio + Math.min(pictures.length - 1, Config.screenshot.pile.shown - 1) * Config.screenshot.pile.offset
    // the right side: the picture, the pile, or nothing
    readonly property real side: shot ? pileWidth : hasPicture && picture.ready ? layout.pictureSize : 0
    readonly property real textX: layout.padding + layout.iconSize + layout.spacing
    readonly property real textWidth: width - textX - layout.padding - (side > 0 ? side + layout.spacing : 0)
    readonly property real textHeight: (caption !== "" ? captionText.implicitHeight + layout.lineSpacing : 0) + titleText.implicitHeight + (body !== "" ? layout.lineSpacing + bodyText.implicitHeight : 0) + (actions.length > 0 ? layout.actionGap + layout.actionHeight : 0)
    width: layout.width
    implicitHeight: 2 * layout.padding + Math.max(textHeight, layout.iconSize, shot ? pileHeight : side)
    // its height follows the content smoothly (hover opens the whole message and the buttons: it grows,
    // the text revealed as it does, and shrinks back), not at once
    property real shownHeight: implicitHeight
    Behavior on shownHeight {
        enabled: card._ready
        NumberAnimation {
            duration: card.layout.hoverDuration
            easing.type: Easing.OutCubic
        }
    }
    property bool _ready: false
    Component.onCompleted: _ready = true
    // folds to nothing as it leaves, its gap in the list included, so the cards below glide up
    property real fold: 1
    height: shownHeight * fold - (1 - fold) * layout.gap

    // ---- swiping it away (a drag, or scrolling): right = deleted (out of the history too), up = off the
    // screen only (a banner: it stays in the history). The drag locks to the way it starts. ----
    property real pull: 0        // sideways, to the right
    property real lift: 0        // upwards (negative)
    transform: Translate {
        x: Math.max(0, card.pull)
        y: Math.min(0, card.lift)
    }
    opacity: 1 - Math.max(Math.max(0, pull) / Math.max(1, width), Math.max(0, -lift) / Math.max(1, height))
    // While a finger moves it, the input sets where it should be (`_toX` / `_toY`) and the card glides there
    // once per frame, a short exponential chase (swipe.follow s): moved on each input event, it stepped
    // (touchpad events don't fall on the screen's frames) and looked jittery
    property real _toX: 0
    property real _toY: 0
    readonly property bool _moving: drag.active || scroller.following
    function follow(x, y) {
        _toX = x;
        _toY = y;
        track();
    }
    FrameAnimation {
        running: card._moving && !exit.running
        onTriggered: {
            const a = 1 - Math.exp(-frameTime / Math.max(0.001, card.layout.swipe.follow));
            card.pull += (card._toX - card.pull) * a;
            card.lift += (card._toY - card.lift) * a;
        }
    }
    // a card open under the pointer (the whole message, its buttons) stays open while it's swiped: moving
    // out from under a still pointer, it collapsed mid-swipe (the layout jumped)
    property bool _keepOpen: false
    on_MovingChanged: if (_moving)
        _keepOpen = hover.hovered
    Behavior on pull {
        enabled: !drag.active && !exit.running && !scroller.following
        SpringAnimation {
            spring: Config.spring(Config.notifications.swipe.spring).spring
            damping: Config.spring(Config.notifications.swipe.spring).damping
            epsilon: 0.5
        }
    }
    Behavior on lift {
        enabled: !drag.active && !exit.running && !scroller.following
        SpringAnimation {
            spring: Config.spring(Config.notifications.swipe.spring).spring
            damping: Config.spring(Config.notifications.swipe.spring).damping
            epsilon: 0.5
        }
    }
    // Its exit, played before it's taken out of the list (removed at once, the list snapped): it carries
    // on from where it is (mid-swipe included), out to the right or up, then folds its height so the cards
    // below glide up, then goes: out of the history (`forGood`), or off the screen only
    // `speed` (px/s, along the way out): a thrown card leaves at the speed it was thrown, no jump at the
    // release. The slide is a cubic Bezier from (0,0) through (1/3, m/3) and (2/3, 1) to (1,1): it starts at
    // slope m and eases to rest off screen. Unthrown, m = 3: exactly OutCubic. Thrown, the duration is the
    // one OutCubic would need to start at that speed (3 * distance / speed), held between swipe.minLeave and
    // leaveDuration, and m = speed * duration / distance: a slow throw starts slow and speeds up, a fast one
    // starts fast and slows (a fixed OutCubic launched a slow throw at ten times its speed).
    function away(forGood, up, speed) {
        if (exit.running)
            return;
        exit.forGood = forGood;
        slideOut.to = up ? pull : card.width + card.layout.margin + card.layout.shadow.blur;
        liftOut.to = up ? -(card.height + card.layout.gap + card.layout.shadow.blur) : lift;
        const left = Math.max(1, up ? lift - liftOut.to : slideOut.to - pull);
        const d = speed > 0 ? 3 * left / speed * 1000 : card.layout.leaveDuration;
        exit.slide = Math.max(card.layout.swipe.minLeave, Math.min(card.layout.leaveDuration, d));
        const m = speed > 0 ? Math.min(3, speed * exit.slide / 1000 / left) : 3;
        exit.curve = [1 / 3, m / 3, 2 / 3, 1, 1, 1];
        exit.start();
    }
    SequentialAnimation {
        id: exit
        property bool forGood: false
        property real slide: card.layout.leaveDuration
        property var curve: [1 / 3, 1, 2 / 3, 1, 1, 1]
        ParallelAnimation {
            NumberAnimation {
                id: slideOut
                target: card
                property: "pull"
                duration: exit.slide
                easing.type: Easing.BezierSpline
                easing.bezierCurve: exit.curve
            }
            NumberAnimation {
                id: liftOut
                target: card
                property: "lift"
                duration: exit.slide
                easing.type: Easing.BezierSpline
                easing.bezierCurve: exit.curve
            }
        }
        // only once it's out of sight do the cards below move up
        NumberAnimation {
            target: card
            property: "fold"
            to: 0
            duration: card.layout.moveDuration
            easing.type: Easing.InOutCubic
        }
        ScriptAction {
            script: {
                if (exit.forGood)
                    Inbox.dismiss(card.uid);
                else
                    Inbox._dropBanner(card.uid);
            }
        }
    }
    // Clear all (the history): every card on screen slides out right, one after the other (`delay`), and
    // stays out; NotificationStack empties the list once they're gone
    function sweep(delay) {
        if (exit.running)
            return;
        sweepPause.duration = delay;
        sweepOut.to = card.width + card.layout.margin + card.layout.shadow.blur;
        sweepAnim.start();
    }
    SequentialAnimation {
        id: sweepAnim
        PauseAnimation {
            id: sweepPause
        }
        NumberAnimation {
            id: sweepOut
            target: card
            property: "pull"
            duration: card.layout.leaveDuration
            easing.type: Easing.OutCubic
        }
    }
    // A throw counts: where the card is when it's let go isn't enough (a quick flick that moved it a little
    // sprang back, as if it was thrown and stayed). Its speed at the end carries it on for
    // swipe.projection seconds (Apple's trick: judge where it would land), and that decides.
    // the card's speed (px/s), a running average that forgets older moves within about a third of
    // swipe.velocityWindow: a pull back at the end of a throw shows within a few events
    property point _speed: Qt.point(0, 0)
    property var _last: null
    function track() {
        const now = Date.now();
        const l = _last;
        if (l && now > l.t) {
            const dt = now - l.t;
            const w = Math.exp(-dt / (layout.swipe.velocityWindow / 3));
            _speed = Qt.point(_speed.x * w + (_toX - l.x) / dt * 1000 * (1 - w), _speed.y * w + (_toY - l.y) / dt * 1000 * (1 - w));
        }
        _last = { "t": now, "x": _toX, "y": _toY };
    }
    // `stale`: a pointer resting before the release throws nothing (its last move longer ago than the window)
    function velocity(stale) {
        if (!_last || (stale && Date.now() - _last.t > layout.swipe.velocityWindow))
            return Qt.point(0, 0);
        return _speed;
    }
    function release(axis, stale) {
        // plain numbers: a point read from a property stays tied to it (reset below, it read 0)
        const v = velocity(stale);
        const vx = v.x, vy = v.y;
        _last = null;
        _speed = Qt.point(0, 0);
        const k = layout.swipe.projection;
        // judged from where the finger put it (the card itself trails it by a frame or two)
        if (axis === "x" && _toX + Math.max(0, vx) * k > layout.swipe.distance && vx > -layout.swipe.backSpeed)
            away(true, false, vx);
        else if (axis === "y" && -(_toY + Math.min(0, vy) * k) > layout.swipe.distance && vy < layout.swipe.backSpeed)
            away(false, true, -vy);
        else {
            _toX = 0;
            _toY = 0;
            pull = 0;
            lift = 0;
            _keepOpen = false;
        }
    }
    DragHandler {
        id: drag
        target: null
        xAxis.enabled: true
        // up only on screen: in the history the list scrolls that way
        yAxis.enabled: !card.inCenter
        // the way the drag started ("" until it has moved swipe.lock px)
        property string axis: ""
        onActiveChanged: {
            if (active) {
                axis = "";
                card._last = null;
                card._speed = Qt.point(0, 0);
                return;
            }
            card.release(axis, true);
        }
        onTranslationChanged: {
            const t = translation;
            if (axis === "" && Math.max(Math.abs(t.x), Math.abs(t.y)) >= card.layout.swipe.lock)
                axis = Math.abs(t.x) >= Math.abs(t.y) || !yAxis.enabled ? "x" : "y";
            card.follow(axis === "x" ? t.x : 0, axis === "y" ? t.y : 0);
        }
    }
    // Scrolling. Two fingers on a touchpad (pixel deltas) move the card like a drag: it follows the way the
    // content would move, locks to the way it started, and when the fingers lift (ScrollEnd, or no event for
    // swipe.scrollEnd ms) it goes away past swipe.distance (right = deleted, up = off the screen) or springs
    // back. A mouse wheel's notch (no pixel deltas) sends it at once past swipe.wheel. In the history,
    // scrolling up and down is the list's: only the sideways handler is on there.
    QtObject {
        id: scroller
        property bool following: false
        property string axis: ""
        property real dx: 0
        property real dy: 0
        function take(event) {
            if (exit.running || drag.active)
                return;
            const p = event.pixelDelta;
            // the fingers lifting: a ScrollEnd with no movement (not a mouse wheel's notch)
            if (event.phase === Qt.ScrollEnd && p.x === 0 && p.y === 0) {
                finish(true);
                return;
            }
            if (p.x === 0 && p.y === 0) {
                // a mouse wheel: one notch is enough
                const a = event.angleDelta;
                if (-a.x > card.layout.swipe.wheel && Math.abs(a.x) >= Math.abs(a.y))
                    card.away(true, false, 0);
                else if (!card.inCenter && a.y > card.layout.swipe.wheel && Math.abs(a.y) > Math.abs(a.x))
                    card.away(false, true, 0);
                return;
            }
            if (event.phase === Qt.ScrollMomentum)
                return;
            if (!following) {
                card._last = null;
                card._speed = Qt.point(0, 0);
            }
            following = true;
            dx += p.x;
            dy += p.y;
            if (axis === "" && Math.max(Math.abs(dx), Math.abs(dy)) >= card.layout.swipe.lock)
                axis = Math.abs(dx) >= Math.abs(dy) || card.inCenter ? "x" : "y";
            card.follow(axis === "x" ? dx : 0, axis === "y" ? dy : 0);
            // a touchpad says when the fingers lift (ScrollEnd): holding still waits for it (judged then: no
            // throw). Only scrolling with no phases (some smooth mouse wheels) ends by a quiet moment.
            if (event.phase === Qt.ScrollEnd)
                finish(true);
            else if (event.phase === Qt.NoScrollPhase)
                scrollEnd.restart();
        }
        function finish(ended) {
            scrollEnd.stop();
            if (!following)
                return;
            following = false;
            const a = axis;
            axis = "";
            dx = 0;
            dy = 0;
            // the fingers lifting (ScrollEnd) is judged like a drag's release; the quiet timer's end only
            // fires after a pause, so it keeps the speed the card had when it last moved
            card.release(a, ended);
        }
    }
    Timer {
        id: scrollEnd
        interval: card.layout.swipe.scrollEnd
        onTriggered: scroller.finish(false)
    }
    // a touchpad counts too: WheelHandler takes only mice by default, and the swipes never arrived
    WheelHandler {
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => scroller.take(event)
    }
    WheelHandler {
        orientation: Qt.Vertical
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: !card.inCenter
        onWheel: event => scroller.take(event)
    }

    // ---- the card ----
    readonly property real corner: Config.corner("menu", height)
    RectangularShadow {
        anchors.fill: face
        radius: card.corner
        blur: card.layout.shadow.blur
        offset.y: card.layout.shadow.offset
        color: Qt.alpha(Config.colors.shadow, card.layout.shadow.opacity)
    }
    Rectangle {
        id: face
        anchors.fill: parent
        radius: card.corner
        color: Config.theme.card
        border.width: card.layout.edgeWidth
        border.color: Qt.alpha(Config.theme.border, card.layout.edgeOpacity)
        palette.windowText: Config.theme.text
        palette.placeholderText: Config.theme.secondary

        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }
        // (not on the × or the buttons: a parent TapHandler also fires for taps on its children)
        TapHandler {
            onTapped: (point, button) => {
                const hit = item => item.visible && item.contains(item.mapFromItem(face, point.position));
                if (hit(close) || hit(actionRow))
                    return;
                Inbox.open(card.uid);
            }
        }

        // ---- left: the app's icon ----
        Item {
            id: iconBox
            x: card.layout.padding
            y: card.layout.padding
            width: card.layout.iconSize
            height: card.layout.iconSize
            Image {
                id: appIcon
                anchors.fill: parent
                readonly property bool ready: status === Image.Ready
                visible: ready && !card.critical
                source: card.hasIcon ? card.row.icon : ""
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                mipmap: true
            }
            // no icon (or urgent, or a screenshot): a soft tile with a glyph, red when urgent
            Rectangle {
                anchors.fill: parent
                visible: !appIcon.visible
                radius: Config.corner("tile", height)
                readonly property color tint: card.critical ? Config.colors.danger : palette.windowText
                color: Qt.alpha(tint, Config.activity.badgeOpacity)
                Icon {
                    anchors.centerIn: parent
                    width: parent.width * card.layout.glyphShare
                    height: width
                    name: card.critical ? card.layout.criticalIcon : card.shot ? card.layout.screenshotIcon : card.layout.fallbackIcon
                    color: parent.tint
                }
            }
        }

        // ---- middle: (app), title + when, message, buttons (clipped to the card while it grows and shrinks) ----
        Item {
            x: card.textX
            width: card.textWidth
            height: Math.max(0, card.height - card.layout.padding)
            clip: true
        Column {
            y: card.layout.padding
            width: card.textWidth
            spacing: card.layout.lineSpacing

            StyledText {
                id: captionText
                visible: text !== ""
                width: parent.width
                elide: Text.ElideRight
                font.pixelSize: card.layout.appNameSize
                color: palette.placeholderText
                text: card.caption
            }
            Item {
                width: parent.width
                height: titleText.implicitHeight
                StyledText {
                    id: titleText
                    anchors.left: parent.left
                    anchors.right: ageText.left
                    anchors.rightMargin: card.layout.spacing
                    elide: Text.ElideRight
                    font.pixelSize: card.layout.summarySize
                    font.weight: card.layout.summaryWeight
                    color: card.critical ? Config.colors.danger : palette.windowText
                    text: card.title
                }
                StyledText {
                    id: ageText
                    anchors.right: parent.right
                    anchors.baseline: titleText.baseline
                    font.pixelSize: card.layout.timeSize
                    color: palette.placeholderText
                    text: card.age
                }
            }
            StyledText {
                id: bodyText
                visible: text !== ""
                width: parent.width
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: card.expanded ? card.layout.bodyLines : card.layout.bodyLinesCollapsed
                font.pixelSize: card.layout.bodySize
                font.weight: card.layout.bodyWeight
                color: palette.placeholderText
                textFormat: card.shot ? Text.PlainText : Text.StyledText
                text: card.body
            }
            // the notification's own buttons (hover; only while the app still has it)
            Row {
                id: actionRow
                visible: card.actions.length > 0
                topPadding: card.layout.actionGap - card.layout.lineSpacing
                spacing: card.layout.actionSpacing
                Repeater {
                    model: card.actions
                    delegate: Rectangle {
                        id: button
                        required property var modelData
                        width: Math.min(buttonLabel.implicitWidth + 2 * card.layout.actionPadding, (card.textWidth - (card.actions.length - 1) * card.layout.actionSpacing) / card.actions.length)
                        height: card.layout.actionHeight
                        radius: Config.corner("pill", height)
                        color: Qt.alpha(palette.windowText, buttonHover.hovered ? card.layout.buttonHoverOpacity : card.layout.buttonOpacity)
                        StyledText {
                            id: buttonLabel
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, button.width - 2 * card.layout.actionPadding)
                            elide: Text.ElideRight
                            font.pixelSize: card.layout.bodySize
                            text: button.modelData.text
                        }
                        HoverHandler {
                            id: buttonHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: Inbox.action(card.uid, button.modelData.id)
                        }
                    }
                }
            }
        }
        }

        // ---- right: the picture ----
        Item {
            id: pictureBox
            visible: !card.shot && card.hasPicture && picture.ready
            x: card.width - card.layout.padding - width
            y: card.layout.padding
            width: card.layout.pictureSize
            height: card.layout.pictureSize
            Image {
                id: picture
                anchors.fill: parent
                readonly property bool ready: status === Image.Ready
                visible: false
                source: card.hasPicture ? card.row.image : ""
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                mipmap: true
            }
            MultiEffect {
                anchors.fill: parent
                source: picture
                maskEnabled: true
                maskSource: pictureMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
            Shape {
                id: pictureMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillColor: "white"
                    PathSvg {
                        path: Config.roundedRectPath(pictureBox.width, pictureBox.height, Config.corner("tile", pictureBox.height), Config.island.cornerSmoothing)
                    }
                }
            }
        }

        // ---- right, a screenshot card: the pile, the newest on top ----
        Item {
            id: pile
            visible: card.shot
            x: card.width - card.layout.padding - card.pileWidth
            y: card.layout.padding
            width: card.pileWidth
            height: card.pileHeight
            Repeater {
                // back to front: the oldest shown first, the newest drawn last (on top)
                model: Math.min(card.pictures.length, Config.screenshot.pile.shown)
                delegate: Item {
                    id: sheet
                    required property int index
                    readonly property int depth: Math.min(card.pictures.length, Config.screenshot.pile.shown) - 1 - index
                    readonly property string path: card.pictures[depth] || ""
                    width: card.pileHeight * card.pileRatio
                    height: card.pileHeight
                    x: card.pileWidth - width - depth * Config.screenshot.pile.offset
                    rotation: depth === 0 ? 0 : (depth % 2 ? -1 : 1) * Config.screenshot.pile.rotation
                    scale: 1 - depth * Config.screenshot.pile.shrink
                    z: -depth
                    readonly property real radius: card.pileHeight * Config.screenshot.roundness
                    Rectangle {
                        anchors.fill: parent
                        radius: sheet.radius
                        color: Config.theme.card
                    }
                    Image {
                        id: sheetImage
                        anchors.fill: parent
                        anchors.margins: Config.screenshot.pile.border
                        visible: false
                        source: sheet.path !== "" ? "file://" + sheet.path.split("/").map(encodeURIComponent).join("/") : ""
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        mipmap: true
                    }
                    MultiEffect {
                        anchors.fill: sheetImage
                        source: sheetImage
                        maskEnabled: true
                        maskSource: sheetMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                        brightness: -sheet.depth * Config.screenshot.pile.darken
                    }
                    Rectangle {
                        id: sheetMask
                        anchors.fill: sheetImage
                        visible: false
                        layer.enabled: true
                        radius: Math.max(0, sheet.radius - Config.screenshot.pile.border)
                    }
                }
            }
        }

        // ---- the ×: top-left corner, half outside (hover), like macOS ----
        Rectangle {
            id: close
            visible: opacity > 0
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Config.motion.hoverFade
                }
            }
            x: -width / 3
            y: -height / 3
            width: card.layout.closeSize
            height: width
            radius: width / 2
            color: Config.theme.card
            border.width: card.layout.closeBorder
            border.color: Qt.alpha(Config.theme.text, card.layout.buttonOpacity)
            Icon {
                anchors.centerIn: parent
                width: parent.width * card.layout.closeIconScale
                height: width
                name: card.layout.closeIcon
                color: Config.theme.text
            }
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: card.away(true, false, 0)
            }
        }
    }
}
