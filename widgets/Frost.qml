import QtQuick

import "../services"

// Marks a frosted surface (panel.blur): niri blurs what's behind its rectangle, with `radius` corners
// (Glass collects them, shell.qml hands them to niri). Fill the surface with it (anchors.fill).
// Its rectangle in the window is worked out here, by walking up its parents and reading each one's x / y,
// so the binding follows anything that moves it: a card sliding in, the history scrolling, the dropdown
// card sliding along the bar. (A Region given the item itself would re-read it only when the item's own
// geometry changes: Quickshell's PendingRegion.) Transforms can't be read in a binding (not bindable):
// an owner moved by a Translate passes it as `dx` / `dy` (a card's swipe, the history's drop-in). The blur can't fade: it's there only while the surface is mostly visible (its and its
// parents' opacity above panel.blur.showAbove). `clipTo`: a list it scrolls in (only the part inside it
// is blurred: the rows kept outside the view aren't drawn).
Item {
    id: frost

    property real radius: 0
    // the owner's own condition on top of being visible enough (e.g. the card is open)
    property bool active: true
    property Item clipTo: null
    // what Translate transforms above it add (see above)
    property real dx: 0
    property real dy: 0

    // ---- where it is, in the window ----
    function _place(item, w, h) {
        let x = 0, y = 0, o = 1;
        for (let it = item; it; it = it.parent) {
            x += it.x;
            y += it.y;
            o *= it.opacity;
        }
        return { "rect": Qt.rect(x, y, w, h), "opacity": o };
    }
    readonly property var _here: _place(frost, width, height)
    readonly property rect rect: {
        const h = _here.rect;
        const r = Qt.rect(h.x + dx, h.y + dy, h.width, h.height);
        if (!clipTo)
            return r;
        const c = _place(clipTo, clipTo.width, clipTo.height).rect;
        const x0 = Math.max(r.x, c.x), y0 = Math.max(r.y, c.y);
        const x1 = Math.min(r.x + r.width, c.x + c.width), y1 = Math.min(r.y + r.height, c.y + c.height);
        return x1 > x0 && y1 > y0 ? Qt.rect(x0, y0, x1 - x0, y1 - y0) : Qt.rect(0, 0, 0, 0);
    }
    // (its own `visible` is already its parents' too; reading each parent's looped, 2026-11-25)
    readonly property bool shown: Config.panel.blur.enabled && active && visible && _here.opacity > Config.panel.blur.showAbove

    Component.onCompleted: Glass.add(frost)
    Component.onDestruction: Glass.remove(frost)
}
