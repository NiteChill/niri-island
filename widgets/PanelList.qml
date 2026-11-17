import QtQuick

import "../services"

// The Wi-Fi and Bluetooth panels' list: a ListView of rows in two groups under small grey titles ("saved"
// then "other": the model's `section` role), a highlight that springs to the selected row, the pointer
// selecting the row under it, edges fading into the island when there's more to scroll (ScrollFade).
// The panel brings the model, the row delegate, the selection and the scrolling maths (it knows its rows'
// heights); the look is shared (panel.list). Only the rows on screen exist (a Repeater over 40 rows froze
// the panel for 650 ms), and the model is updated in place.
Item {
    id: list

    // ---- in ----
    property alias model: view.model
    property alias delegate: view.delegate
    property alias footer: view.footer
    property int selected: 0
    // the pointer may change the selection (false while a row is busy with the keyboard, e.g. a password)
    property bool pointerSelects: true
    property int savedCount: 0
    property string savedTitle
    property string otherTitle
    // the pointer moved onto row `index` (the panel decides whether to select it)
    signal pointed(int index)

    readonly property var cfg: Config.panel.list
    readonly property alias view: view
    // where the list is scrolled, or heading to while the scroll animation runs
    readonly property real scrollTarget: scrollAnim.running ? scrollAnim.to : view.contentY

    // scroll (animated) to y, kept inside a list `fullHeight` tall
    function scrollTo(y, fullHeight) {
        y = Math.max(0, Math.min(y, fullHeight - height));
        if (y === view.contentY && !scrollAnim.running)
            return;
        scrollAnim.stop();
        scrollAnim.to = y;
        scrollAnim.start();
    }
    // back to the top at once (the panel opening)
    function reset() {
        scrollAnim.stop();
        view.positionViewAtBeginning();
    }
    // the selection follows `selected`, set rather than bound: ListView moves its own currentIndex on inserts
    onSelectedChanged: view.currentIndex = selected
    function syncCurrent() {
        view.currentIndex = selected;
    }

    ListView {
        id: view
        anchors.fill: parent
        // blurred island: faded through a mask instead of a band in the island color (ScrollFade)
        layer.enabled: edgeFade.masked
        layer.effect: edgeFade.effect
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: list.cfg.rowHeight * Config.panel.visibleRows
        highlightFollowsCurrentItem: false

        NumberAnimation {
            id: scrollAnim
            target: view
            property: "contentY"
            duration: list.cfg.scrollDuration
            easing.type: Easing.OutCubic
        }

        // group titles (saved / other)
        section.property: "section"
        section.delegate: Item {
            id: sectionItem
            required property string section
            // a gap above the second group
            readonly property real gap: section === "other" && list.savedCount > 0 ? list.cfg.sectionGap : 0
            width: view.width
            height: list.cfg.headerHeight + gap
            StyledText {
                x: list.cfg.rowPadding
                y: sectionItem.gap
                height: list.cfg.headerHeight
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Config.activity.captionSize
                color: Config.colors.secondary
                text: sectionItem.section === "saved" ? list.savedTitle : list.otherTitle
            }
        }

        // highlight that springs to the selected row
        highlight: Rectangle {
            visible: view.count > 0
            width: view.width
            height: list.cfg.rowHeight
            radius: Config.corner("row", height)
            color: Config.colors.text
            opacity: list.cfg.selectedOpacity
            y: view.currentItem ? view.currentItem.y : 0
            Behavior on y {
                SpringAnimation {
                    spring: Config.spring(list.cfg.highlight).spring
                    damping: Config.spring(list.cfg.highlight).damping
                    epsilon: 0.25
                }
            }
        }

        // The pointer selects the row under it only when it actually moves: rows change (and the list
        // scrolls) under a still pointer, and selecting on plain hover made the selection jump around.
        // Scrolling with the wheel / a drag does select the row that ends up under the pointer (the
        // keyboard's own scrolling doesn't, or the two would fight).
        // Note: a handler declared inside a ListView lands on its contentItem, so point.position is
        // already in content coordinates and moves when the list scrolls. Work from the scene position
        // instead, mapped to the view, then add contentY once.
        HoverHandler {
            id: listHover
            property point lastScene: Qt.point(-1, -1)
            function selectUnderPointer() {
                if (!hovered || !list.pointerSelects)
                    return;
                const p = view.mapFromItem(null, lastScene.x, lastScene.y);
                const i = view.indexAt(p.x, p.y + view.contentY);
                if (i >= 0 && i !== list.selected)
                    list.pointed(i);
            }
            onPointChanged: {
                const p = point.scenePosition;
                if (p.x === lastScene.x && p.y === lastScene.y)
                    return;   // the rows moved under a still pointer (a scan update), not the mouse
                lastScene = p;
                selectUnderPointer();
            }
        }
        onContentYChanged: {
            if (!scrollAnim.running)
                listHover.selectUnderPointer();
        }
    }

    // edges fade into the island when there's more to scroll that way (a mask when blurred)
    ScrollFade {
        id: edgeFade
        anchors.fill: view
        view: view
        size: list.cfg.scrollFade
        active: list.visible
    }
}
