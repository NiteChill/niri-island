pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

import "../services"

// A carousel of pictures (the wallpaper picker and the shelf, in the notch; look in `carousel.*`): the selected
// card in front, carousel.side.count neighbours behind it on each side (smaller, turned, darker), the
// next ones fading in from further out as the row slides (one spring, carousel.move). Left / Right (the
// panel's keys call step()), the wheel, a drag or a click on a side card pick; a click on the front card
// emits activated(index). Past the ends the row bumps; press() sinks the front card a little and springs
// it back (the panel's "done": applied, copied). `markedPath` wears a check badge (carousel.mark.*).
// Only 2 * side.count + 3 cards exist: each one takes the next picture when it leaves the row on one side,
// so a folder of any size costs the same, and a picture keeps its card while it moves through the row.
// Cards: all in `ratio` (wallpapers: the screen's), or, given `ratios` (one per picture), each in its
// picture's proportions held between minRatio and maxRatio (screenshots: a thin one gets a normal card,
// the picture cropped around its centre). The pictures always fill their card. Neighbours sit closer
// to a narrow card, further from a wide one (side.offset is the spacing of the widest cards).
// dragOut: the front card can be dragged up or down out of the island and dropped anywhere that takes
// files (a mail being written, a browser's upload area, a chat, a folder): a real drag of the file, as a
// file:// address and as a file transfer portal key (Sys.offerFile: sandboxed apps get the file itself,
// not a path they can't open). While it runs, Activity.draggingOut keeps the panel open and lets the
// drop reach the window under the pointer.
Item {
    id: carousel

    readonly property var look: Config.carousel

    property var pictures: []
    readonly property int count: pictures.length
    // what each card shows, when it isn't the file itself (the shelf: a PDF's thumbnail); "" = no picture:
    // the card shows `icons` (the file type's icon) and `names` instead. Empty lists = the files are pictures.
    property var previews: []
    property var icons: []
    property var names: []
    property string markedPath: ""
    // what the marked picture wears: a glyph (the wallpaper in use: a check) and an optional word (the
    // screenshot just copied: a copy glyph + "Copied")
    property string markIcon: look.mark.icon
    property string markLabel: ""
    property bool dragOut: false
    // the width the row may take, and the cards' proportions (width / height)
    property real availableWidth: 0
    property real ratio: 16 / 10
    // per picture (0 = unknown: `ratio`); empty = every card in `ratio`
    property var ratios: []
    property real minRatio: 0.75
    property real maxRatio: 1.78
    readonly property bool flexible: ratios.length > 0

    signal picked(int index)      // the user moved the selection
    signal activated(int index)   // a click on the front card
    signal secondaryActivated(int index)   // a right click on the front card
    // an × on the front card's top-left corner (the shelf: off it); "" = none. It's part of the card: it
    // moves, turns and fades with it as the row slides
    property string removeIcon: ""
    property real removeSize: 0
    property real removeInset: 0
    property real removeGlyph: 0
    signal removeRequested(int index)
    // a picture on its way out (the shelf's ×): its card shrinks and fades over look.leave.duration
    property string leavingPath: ""

    // ---- sizes: the front card takes what the side cards leave ----
    readonly property int side: look.side.count
    readonly property int slots: 2 * side + 3
    // the widest card (all cards, when they share one ratio)
    readonly property real cardW: Math.max(0, 2 * (availableWidth / 2 - side * look.side.offset) / Math.pow(look.side.scale, side))
    readonly property real cardH: Math.round(cardW / (flexible ? maxRatio : ratio))
    function widthOf(i) {
        if (!flexible)
            return cardW;
        const r = ratios[i] > 0 ? ratios[i] : ratio;
        return Math.round(cardH * Math.max(minRatio, Math.min(maxRatio, r)));
    }
    // where each picture's card centre sits along the row (picture 0 at 0). Between the widest cards,
    // side.offset; otherwise spaced so a neighbour behind the front card shows the same strip of itself
    // as between the widest (`peek`), averaged over which of the two is in front, so it slides smoothly
    readonly property real peek: look.side.offset - cardW * (1 - look.side.scale) / 2
    function gapAfter(i) {
        return (widthOf(i) + widthOf(i + 1)) * (1 - look.side.scale) / 4 + peek;
    }
    readonly property var centres: {
        const c = [0];
        for (let i = 1; i < count; i++)
            c.push(c[i - 1] + gapAfter(i - 1));
        return c;
    }
    // the centre of a position along the row (between two pictures while it slides, past the ends while
    // it bumps)
    function centreAt(x) {
        if (count === 0)
            return 0;
        const i = Math.max(0, Math.min(count - 1, Math.floor(x)));
        const step = i < count - 1 ? gapAfter(i) : look.side.offset;
        return centres[i] + (x - i) * step;
    }
    readonly property real stageW: 2 * (side * look.side.offset + cardW * Math.pow(look.side.scale, side) / 2)
    readonly property real stageH: cardH
    implicitWidth: stageW
    implicitHeight: stageH

    // ---- selection ----
    property int selected: 0
    property string selectedPath: ""
    // the row's position (index of the card in front; between two while it slides): springs to `selected`
    property real pos: 0
    property bool springy: true
    Behavior on pos {
        enabled: carousel.springy
        SpringAnimation {
            spring: Config.spring(carousel.look.move).spring
            damping: Config.spring(carousel.look.move).damping
            epsilon: 0.001
        }
    }
    // pushed past an end: the row slides a little that way and springs back (bump)
    property real nudge: 0
    readonly property real at: pos + nudge
    property real wheelSum: 0

    function select(i, animate) {
        if (count === 0)
            return;
        i = Math.max(0, Math.min(count - 1, i));
        selected = i;
        selectedPath = pictures[i];
        if (animate) {
            pos = i;
        } else {
            springy = false;
            pos = i;
            springy = true;
        }
    }
    function pick(i) {
        select(i, true);
        picked(selected);
    }
    function step(d) {
        if (count === 0)
            return;
        if (selected + d < 0 || selected + d >= count)
            bump(d);
        else
            pick(selected + d);
    }
    // the list changed: find the picture `path` again, jumping. Gone (removed): the selection stays at
    // the same place, and the card that takes it slides in from where it was (the next one from the
    // right; the last one removed: the one before, from the left)
    function relocate(path) {
        const i = path ? pictures.indexOf(path) : -1;
        if (i >= 0 || count === 0) {
            select(Math.max(0, i), false);
            return;
        }
        const k = Math.min(selected, count - 1);
        springy = false;
        pos = selected < count ? k - 1 : selected;
        springy = true;
        select(k, true);
    }

    // ---- bump (an end reached) ----
    function bump(d) {
        nudgeBack.stop();
        nudgeOut.to = d * look.bump.distance;
        nudgeOut.restart();
    }
    NumberAnimation {
        id: nudgeOut
        target: carousel
        property: "nudge"
        duration: carousel.look.bump.duration
        easing.type: Easing.OutCubic
        onFinished: nudgeBack.start()
    }
    SpringAnimation {
        id: nudgeBack
        target: carousel
        property: "nudge"
        to: 0
        spring: Config.spring(carousel.look.bump.spring).spring
        damping: Config.spring(carousel.look.bump.spring).damping
        epsilon: 0.001
    }

    // ---- done (applied, copied): the front card sinks a little and springs back ----
    property real pulse: 0
    function press() {
        pulseBack.stop();
        pulseIn.restart();
    }
    NumberAnimation {
        id: pulseIn
        target: carousel
        property: "pulse"
        to: 1
        duration: carousel.look.press.duration
        easing.type: Easing.OutCubic
        onFinished: pulseBack.start()
    }
    SpringAnimation {
        id: pulseBack
        target: carousel
        property: "pulse"
        to: 0
        spring: Config.spring(carousel.look.press.spring).spring
        damping: Config.spring(carousel.look.press.spring).damping
        epsilon: 0.001
    }

    // the card under a point: the nearest to the front whose outline holds it (-1 = none)
    function cardAt(px, py) {
        const dx = px - width / 2, dy = py - height / 2;
        let best = -1, bestDist = Infinity;
        for (let i = Math.floor(at) - side; i <= Math.ceil(at) + side; i++) {
            if (i < 0 || i >= count)
                continue;
            const rel = i - at, dist = Math.abs(rel);
            const s = Math.pow(look.side.scale, dist);
            if (Math.abs(dx - (centres[i] - centreAt(at))) <= widthOf(i) * s / 2 && Math.abs(dy) <= cardH * s / 2 && dist < bestDist) {
                best = i;
                bestDist = dist;
            }
        }
        return best;
    }

    // the point is on the front card's × (its own handler takes it: a parent TapHandler also fires for
    // taps on its children, which opened the file too)
    function onRemove(px, py) {
        if (removeIcon === "" || count === 0)
            return false;
        const x0 = width / 2 - widthOf(selected) / 2 + removeInset, y0 = height / 2 - cardH / 2 + removeInset;
        return px >= x0 && px <= x0 + removeSize && py >= y0 && py <= y0 + removeSize;
    }
    // ---- the card under the pointer (any of them) tilts toward it in 3D and a soft shine follows it
    // (carousel.tilt.*, carousel.shine.*); each card works out where the pointer is on itself ----
    property point pointer: Qt.point(-1, -1)
    property bool pointerIn: false
    function aim(px, py) {
        pointer = Qt.point(px, py);
        pointerIn = !Activity.draggingOut;
    }
    function rest() {
        pointerIn = false;
    }
    HoverHandler {
        cursorShape: Qt.PointingHandCursor
        onPointChanged: {
            if (hovered)
                carousel.aim(point.position.x, point.position.y);
        }
        onHoveredChanged: {
            if (!hovered)
                carousel.rest();
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: point => {
            const i = carousel.cardAt(point.position.x, point.position.y);
            if (i === carousel.selected)
                carousel.secondaryActivated(i);
            else if (i >= 0)
                carousel.pick(i);
        }
    }
    TapHandler {
        onTapped: point => {
            if (carousel.onRemove(point.position.x, point.position.y))
                return;
            const i = carousel.cardAt(point.position.x, point.position.y);
            if (i < 0)
                return;
            if (i === carousel.selected)
                carousel.activated(i);
            else
                carousel.pick(i);
        }
    }
    // a sideways drag slides the row; let go and it settles on the nearest card (a flick carries on)
    property real dragFrom: 0
    DragHandler {
        id: slide
        target: null
        yAxis.enabled: false
        onActiveChanged: {
            if (active) {
                carousel.dragFrom = carousel.pos;
                carousel.springy = false;
                carousel.pos = carousel.dragFrom;   // stops a slide still running (the Behavior is off)
            } else {
                carousel.springy = true;
                carousel.pick(Math.round(carousel.pos - centroid.velocity.x * carousel.look.drag.momentum / carousel.look.side.offset));
            }
        }
        onTranslationChanged: if (active)
            carousel.pos = Math.max(-carousel.look.drag.overscroll, Math.min(carousel.count - 1 + carousel.look.drag.overscroll, carousel.dragFrom - translation.x / carousel.look.side.offset))
    }
    // one card per wheel notch (120 = one notch); touchpads add up their small steps
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            carousel.wheelSum -= event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
            while (Math.abs(carousel.wheelSum) >= 120) {
                const d = carousel.wheelSum > 0 ? 1 : -1;
                carousel.wheelSum -= d * 120;
                carousel.step(d);
            }
        }
    }

    // ---- drag the front picture out (dragOut) ----
    // an up / down drag on the front card (sideways slides the row): a system drag of the file
    function fileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }
    Item {
        id: outDrag
        // over the front card
        readonly property real w: carousel.widthOf(carousel.selected)
        x: (carousel.width - w) / 2
        y: (carousel.height - carousel.cardH) / 2
        width: w
        height: carousel.cardH
        enabled: carousel.dragOut && carousel.count > 0
        readonly property string path: carousel.count > 0 ? carousel.pictures[carousel.selected] || "" : ""
        // the portal key for it (asked for as soon as it's in front, so it's there when the drag starts)
        readonly property string key: path ? Sys.transferKeys[path] || "" : ""
        // (again whenever the keys are gone: the helper stops when the panel closes)
        readonly property bool wantsKey: enabled && path !== "" && key === "" && Sys.fileTransfer
        onWantsKeyChanged: if (wantsKey)
            Sys.offerFile(path)
        Drag.dragType: Drag.None   // started by hand (startDrag), see lift below
        Drag.supportedActions: Qt.CopyAction
        Drag.proposedAction: Qt.CopyAction
        // the portal key first (GTK and Firefox take it over a path), then the address for the rest;
        // no plain text: a text field would take the path as text
        Drag.mimeData: {
            if (!path)
                return {};
            const m = {};
            if (key) {
                m["application/vnd.portal.filetransfer"] = key;
                m["application/vnd.portal.files"] = key;
            }
            m["text/uri-list"] = carousel.fileUrl(path) + "\r\n";
            return m;
        }
        // the picture under the pointer while dragging: the card's preview, else the file type's icon
        readonly property string dragPicture: carousel.count === 0 ? "" : carousel.previews.length === 0 ? (path ? carousel.fileUrl(path) : "") : carousel.previews[carousel.selected] ? carousel.fileUrl(carousel.previews[carousel.selected]) : carousel.icons[carousel.selected] || ""
        Drag.imageSource: dragPicture
        readonly property real imageH: Math.round(carousel.look.dragOut.imageWidth * carousel.cardH / Math.max(1, w))
        Drag.imageSourceSize: Qt.size(carousel.look.dragOut.imageWidth, imageH)
        Drag.hotSpot.x: carousel.look.dragOut.imageWidth / 2
        Drag.hotSpot.y: imageH / 2
        // the system drag holds the pointer until the drop, and the DragHandler loses it the moment the
        // drag starts: so Activity.draggingOut is set here and cleared only when the drop is done. The
        // click-outside layer is unmapped first, and the drag starts a moment later
        // (carousel.dragOut.startDelay), or it would still cover the window you drop on.
        DragHandler {
            id: lift
            target: null
            xAxis.enabled: false
            onActiveChanged: {
                if (!active || Activity.draggingOut)
                    return;
                Activity.draggingOut = true;
                startLater.restart();
            }
        }
        Timer {
            id: startLater
            interval: carousel.look.dragOut.startDelay
            onTriggered: {
                // blocks until the drop (or Escape) while events keep flowing
                outDrag.Drag.active = true;
                outDrag.Drag.startDrag(Qt.CopyAction);
                outDrag.Drag.active = false;
                Activity.draggingOut = false;
            }
        }
    }

    Repeater {
        model: carousel.slots
        delegate: Item {
            id: card
            required property int index
            // which picture this card holds: the one of the visible window that is `index` modulo slots
            readonly property int first: Math.round(carousel.at) - Math.floor(carousel.slots / 2)
            readonly property int pic: first + (((index - first) % carousel.slots) + carousel.slots) % carousel.slots
            readonly property bool exists: pic >= 0 && pic < carousel.count
            readonly property string path: exists ? carousel.pictures[pic] : ""
            readonly property string preview: !exists ? "" : carousel.previews.length > 0 ? carousel.previews[pic] || "" : path
            readonly property bool iconOnly: exists && preview === ""
            readonly property real rel: pic - carousel.at
            readonly property real dist: Math.abs(rel)
            // 1 in front, 0 from one place away: how much the press moves it
            readonly property real front: Math.max(0, 1 - dist)
            // on its way out (leavingPath): 0 -> 1, shrinking and fading (only one way: the slot then holds
            // another picture, which must not fade back in)
            readonly property bool leaving: path !== "" && path === carousel.leavingPath
            property real gone: leaving ? 1 : 0
            Behavior on gone {
                enabled: card.leaving
                NumberAnimation {
                    duration: carousel.look.leave.duration
                    easing.type: Easing.OutCubic
                }
            }

            visible: exists && dist < carousel.side + 1
            width: exists ? carousel.widthOf(pic) : carousel.cardW
            height: carousel.cardH
            x: carousel.width / 2 - width / 2 + (exists ? carousel.centres[pic] - carousel.centreAt(carousel.at) : rel * carousel.look.side.offset)
            y: carousel.height / 2 - height / 2
            z: -dist
            opacity: Math.max(0, Math.min(1, carousel.side + 1 - dist)) * (1 - gone)
            scale: Math.pow(carousel.look.side.scale, dist) * (1 - carousel.look.press.depth * carousel.pulse * front) * (1 - (1 - carousel.look.leave.scale) * gone)
            rotation: Math.max(-1, Math.min(1, rel)) * carousel.look.side.rotation
            // the hover tilt (the card under the pointer: card.tiltX / tiltY, below), in perspective: a viewer carousel.tilt.depth px away (Qt's
            // own Rotation puts it 1024 px away: a 7 degree tilt moved the edges by 3 px, unseen)
            readonly property real ax: tiltX * Math.PI / 180
            readonly property real ay: tiltY * Math.PI / 180
            transform: Matrix4x4 {
                matrix: {
                    const cx = card.width / 2, cy = card.height / 2, d = carousel.look.tilt.depth;
                    const ca = Math.cos(card.ax), sa = Math.sin(card.ax), cb = Math.cos(card.ay), sb = Math.sin(card.ay);
                    // R = Ry * Rx
                    const r = [cb, sb * sa, sb * ca, 0, ca, -sa, -sb, cb * sa, cb * ca];
                    // M = T(c) * P * R * T(-c), P = perspective (w = 1 - z / d). The depth isn't rotated (z row =
                    // identity: the card is flat, z = 0): rotated, the tilted card went "behind" its neighbours
                    // and was cut by them; a zero row instead made the matrix singular and the vector icons on
                    // the card (the check, the x) vanished
                    const m = Qt.matrix4x4(r[0], r[1], r[2], 0, r[3], r[4], r[5], 0, 0, 0, 1, 0, -r[6] / d, -r[7] / d, -r[8] / d, 1);
                    return Qt.matrix4x4(1, 0, 0, cx, 0, 1, 0, cy, 0, 0, 1, 0, 0, 0, 0, 1).times(m).times(Qt.matrix4x4(1, 0, 0, -cx, 0, 1, 0, -cy, 0, 0, 1, 0, 0, 0, 0, 1));
                }
            }
            // ---- what sets the card apart from the island (carousel.backing.style): a dark picture on the
            // dark island has no edge otherwise ----
            // glow: the picture itself, very blurred and a little brighter, spreading around its card (the
            // front one at glow.opacity, the ones behind at glow.sideOpacity of it)
            MultiEffect {
                readonly property var g: carousel.look.backing.glow
                visible: carousel.look.backing.style === "glow" && picture.status === Image.Ready && opacity > 0
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                scale: 1 + g.spread / Math.max(1, card.height)
                source: picture
                autoPaddingEnabled: true
                blurEnabled: true
                blur: 1
                blurMax: g.blur
                brightness: g.brightness
                saturation: g.saturation
                opacity: g.opacity * (card.front + (1 - card.front) * g.sideOpacity)
            }
            // lift: a faint light under every card, soft edged
            RectangularShadow {
                readonly property var l: carousel.look.backing.lift
                visible: carousel.look.backing.style === "lift"
                anchors.fill: parent
                radius: Config.corner("tile", card.height)
                blur: l.blur
                spread: l.spread
                color: Qt.alpha(palette.windowText, l.opacity)
            }
            // the picture, decoded at the card's size on screen, off the main thread
            readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
            // the card's rounded outline (the picture's mask)
            Shape {
                id: mask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillColor: palette.windowText
                    PathSvg {
                        path: Config.roundedRectPath(card.width, card.height, Config.corner("tile", card.height), Config.island.cornerSmoothing)
                    }
                }
            }
            // a tile while the picture loads: opaque (the badges' tint over the island's color), so the
            // cards behind don't show through; darker behind, like the pictures
            Rectangle {
                anchors.fill: parent
                visible: picture.status !== Image.Ready
                radius: Config.corner("tile", height)
                color: Qt.tint(Qt.tint(palette.window, Qt.alpha(palette.windowText, Config.activity.badgeOpacity)), Qt.alpha("#000000", carousel.look.side.dim * Math.min(1, card.dist)))
            }
            Image {
                id: picture
                anchors.fill: parent
                visible: false
                source: card.preview ? carousel.fileUrl(card.preview) : ""
                sourceSize.width: Math.ceil(card.width * card.dpr) || 0
                sourceSize.height: Math.ceil(card.height * card.dpr) || 0
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            // no picture (a text file, a folder): the file type's icon and the name on the tile
            Column {
                visible: card.iconOnly
                anchors.centerIn: parent
                width: parent.width - 2 * carousel.look.file.padding
                spacing: carousel.look.file.gap
                opacity: 1 - carousel.look.side.dim * Math.min(1, card.dist)
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(carousel.look.file.iconSize, card.height * carousel.look.file.iconShare)
                    height: width
                    source: card.iconOnly ? carousel.icons[card.pic] || "" : ""
                    sourceSize.width: width * card.dpr
                    sourceSize.height: height * card.dpr
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    font.pixelSize: carousel.look.file.nameSize
                    text: card.iconOnly ? carousel.names[card.pic] || "" : ""
                }
            }
            // rounded through the shared mask; the cards behind darker
            MultiEffect {
                anchors.fill: parent
                visible: picture.status === Image.Ready
                source: picture
                maskEnabled: true
                maskSource: mask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
                brightness: -carousel.look.side.dim * Math.min(1, card.dist)
            }
            // the shine: a soft, wide light where the pointer is on this card (any card, not only the front
            // one), in the card's own rounded outline; it fades in and out with the pointer
            readonly property point shineAt: carousel.pointerIn ? mapFromItem(carousel, carousel.pointer.x, carousel.pointer.y) : Qt.point(-1, -1)
            readonly property bool shining: exists && shineAt.x >= 0 && shineAt.x <= width && shineAt.y >= 0 && shineAt.y <= height
            property point shineSpot: Qt.point(width / 2, height / 2)
            onShineAtChanged: if (shining)
                shineSpot = shineAt
            property real shineLevel: shining ? 1 : 0
            // the tilt toward the pointer while it's on this card, springing back flat when it leaves
            property real tiltX: shining && carousel.look.tilt.enabled ? -(shineAt.y / height - 0.5) * 2 * carousel.look.tilt.max : 0
            property real tiltY: shining && carousel.look.tilt.enabled ? (shineAt.x / width - 0.5) * 2 * carousel.look.tilt.max : 0
            Behavior on tiltX {
                SpringAnimation {
                    spring: Config.spring(carousel.look.tilt.spring).spring
                    damping: Config.spring(carousel.look.tilt.spring).damping
                    epsilon: 0.01
                }
            }
            Behavior on tiltY {
                SpringAnimation {
                    spring: Config.spring(carousel.look.tilt.spring).spring
                    damping: Config.spring(carousel.look.tilt.spring).damping
                    epsilon: 0.01
                }
            }
            Behavior on shineLevel {
                NumberAnimation {
                    duration: carousel.look.shine.fade
                    easing.type: Easing.OutCubic
                }
            }
            Shape {
                anchors.fill: parent
                visible: opacity > 0
                opacity: carousel.look.shine.enabled ? card.shineLevel * carousel.look.shine.opacity : 0
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: card.shineSpot.x
                        centerY: card.shineSpot.y
                        focalX: centerX
                        focalY: centerY
                        centerRadius: Math.max(card.width, card.height) * carousel.look.shine.radius
                        focalRadius: 0
                        // a soft falloff (a middle stop): diffuse, no bright core
                        GradientStop {
                            position: 0
                            color: "#ffffff"
                        }
                        GradientStop {
                            position: 0.5
                            color: Qt.rgba(1, 1, 1, carousel.look.shine.middle)
                        }
                        GradientStop {
                            position: 1
                            color: "#00ffffff"
                        }
                    }
                    PathSvg {
                        path: Config.roundedRectPath(card.width, card.height, Config.corner("tile", card.height), Config.island.cornerSmoothing)
                    }
                }
            }
            // the × (removeIcon), on the front card only: dark and solid, it reads on a white page too
            Badge {
                visible: carousel.removeIcon !== "" && opacity > 0
                x: carousel.removeInset
                y: carousel.removeInset
                z: 2
                height: carousel.removeSize
                outerCorner: Config.corner("tile", card.height)
                inset: carousel.removeInset
                solid: true
                tint: Config.island.color
                glyphColor: Config.colors.text
                icon: carousel.removeIcon
                glyphSize: carousel.removeGlyph
                opacity: Math.max(0, 1 - 2 * card.dist)
                clickable: card.dist < 0.5
                onClicked: carousel.removeRequested(card.pic)
            }
            // the marked picture (the wallpaper in use, the screenshot just copied)
            Badge {
                readonly property bool marked: card.path !== "" && card.path === carousel.markedPath
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: carousel.look.mark.inset
                height: carousel.look.mark.size
                outerCorner: Config.corner("tile", card.height)
                inset: carousel.look.mark.inset
                solid: true
                tint: Config.colors.accent
                icon: carousel.markIcon
                label: carousel.markLabel
                glyphSize: carousel.look.mark.glyphSize
                opacity: marked ? 1 : 0
                scale: marked ? 1 : carousel.look.mark.hiddenScale
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Config.motion.colorFade
                    }
                }
                Behavior on scale {
                    SpringAnimation {
                        spring: Config.spring(carousel.look.mark.spring).spring
                        damping: Config.spring(carousel.look.mark.spring).damping
                        epsilon: 0.001
                    }
                }
            }
        }
    }
}
