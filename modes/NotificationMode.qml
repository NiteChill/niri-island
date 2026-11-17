pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

import "../services"
import "../island"
import "../widgets"

// Island mode (an activity, put up by Activity): a notification, the island's two-line language.
//  - leading: the notification's picture (a person, a cover...) with the app's icon cut into its corner,
//    like the iPhone's; else the app's icon; else a soft badge-style tile with a bell. Concentric with the
//    island's end. Urgent ones (critical) take the danger red there: a red tile with notifications.criticalIcon.
//  - the title in white (the app's name when there's none), the message in grey under it: one line,
//    the whole text on hover. The app's name only when nothing else says who it's from (no icon, no
//    picture), or on request (notifications.showAppName).
//  - no "now": the age shows only when the notification waited to be seen (notifications.ageAfter, e.g.
//    covered by a panel): "3m ago" after the title
//  - entrance (onAppeared): the icon springs up from notifications.appear.iconFrom, the text rises in
//    just after
// Hover: it opens up in place to the whole text and the notification's buttons, with a close button.
// Click: runs the notification's main action and brings up the window that sent it (a system
// sender: its Settings page; a closed app: starts it), then closes it. Scroll up: dismisses it.
IslandMode {
    id: mode

    readonly property var layout: Config.notifications

    // the notification shown, and a copy of its fields: the copy outlives the notification while
    // island fades it out after it's gone
    property var notification: null
    property var info: null
    property double since: 0
    function refresh() {
        const c = Activity.current;
        if (!c || c.kind !== "notification")
            return;
        const swapped = c.data !== notification && notification !== null && active;
        if (swapped)
            swapAnim.restart();   // another notification takes the place: quick fade between them
        notification = c.data;
        info = Sys.notificationInfo(c.data);
        since = c.since;
        if (swapped)
            enter();
    }
    Connections {
        target: Activity
        function onCurrentChanged() {
            mode.refresh();
        }
    }

    // (onScreen: it stays as it was while animating out, instead of collapsing mid-fade)
    readonly property bool expanded: layout.expandOnHover && onScreen && hover.hovered
    readonly property var actions: info ? info.actions.slice(0, layout.maxActions) : []
    readonly property bool hasPicture: !!info && info.image !== ""
    readonly property bool hasAppIcon: !!info && info.icon !== ""
    readonly property string title: info ? (info.summary || info.appName) : ""
    readonly property bool critical: !!info && info.urgency === "critical"
    // the app's name above the title: asked for, or nothing else would say who it's from
    readonly property string caption: info && info.summary !== "" && info.appName !== "" && (layout.showAppName || (!hasPicture && !appIcon.ready)) ? info.appName : ""
    // minutes it has been waiting; shown from notifications.ageAfter on
    readonly property int age: Math.floor((Sys.time.getTime() - since) / 60000)
    readonly property bool showAge: since > 0 && layout.ageAfter > 0 && age >= layout.ageAfter

    implicitWidth: layout.width
    // from the lines' sizes, not column.implicitHeight: a Column skips hidden children, and the mode is
    // hidden until it fades in, so the island first sprang to a shorter size, then changed course mid-way
    readonly property real textHeight: (caption !== "" ? captionText.height + layout.lineSpacing : 0) + titleRow.height + (bodyText.text !== "" ? layout.lineSpacing + bodyText.height : 0) + (expanded && actions.length > 0 ? layout.lineSpacing + layout.actionGap + layout.actionHeight : 0)
    readonly property real innerHeight: Math.max(layout.iconSize, textHeight)
    implicitHeight: 2 * layout.padding + innerHeight
    // the leading tile hugs the island's rounded end: its corner is the island's minus the padding
    readonly property real tileCorner: Config.inner(Config.corner("island", implicitHeight), layout.padding, layout.iconSize)

    // ---- entrance: the icon springs up, the text rises in just after ----
    property real iconIn: 1
    property real textIn: 1
    function enter() {
        iconSpring.stop();
        textRise.stop();
        iconIn = 0;
        textIn = 0;
        if (hasAppeared) {
            iconSpring.start();
            textRise.start();
        }
    }
    onActiveChanged: if (active)
        enter()
    onAppeared: {
        iconSpring.start();
        textRise.start();
    }
    SpringAnimation {
        id: iconSpring
        target: mode
        property: "iconIn"
        to: 1
        spring: Config.spring(mode.layout.appear.spring).spring
        damping: Config.spring(mode.layout.appear.spring).damping
        epsilon: 0.001
    }
    SequentialAnimation {
        id: textRise
        PauseAnimation {
            duration: mode.layout.appear.textDelay
        }
        NumberAnimation {
            target: mode
            property: "textIn"
            to: 1
            duration: mode.layout.appear.textDuration
            easing.type: Easing.OutCubic
        }
    }

    // ---- input ----
    HoverHandler {
        id: hover
    }
    // (not on the close button or the notification's buttons: a parent TapHandler also fires for taps
    // on its children, which ran the main action on top of theirs)
    function hitsControl(pos) {
        const hit = item => item.visible && item.contains(item.mapFromItem(mode, pos));
        return hit(close) || hit(actionRow);
    }
    TapHandler {
        onTapped: (point, button) => {
            if (mode.hitsControl(point.position))
                return;
            // its own action, then the window that sent it, or the Settings page for a system one
            // (Sys.openNotification)
            Sys.openNotification(mode.notification);
            if (mode.layout.clickDismisses || !(mode.info && mode.info.hasDefault))
                Sys.dismissNotification(mode.notification);
        }
    }
    WheelHandler {
        onWheel: event => {
            if (event.angleDelta.y > 0)
                Sys.dismissNotification(mode.notification);
        }
    }

    // ---- content ----
    Item {
        id: content
        x: mode.layout.padding
        y: mode.layout.padding
        width: mode.implicitWidth - 2 * mode.layout.padding
        height: mode.innerHeight

        SequentialAnimation {
            id: swapAnim
            NumberAnimation {
                target: content
                property: "opacity"
                to: 0
                duration: mode.layout.swapFade / 2
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: content
                property: "opacity"
                to: 1
                duration: mode.layout.swapFade / 2
                easing.type: Easing.OutQuad
            }
        }

        // ---- leading: the picture (+ the app's icon cut into its corner), the app's icon, or a bell ----
        Item {
            id: iconBox
            width: mode.layout.iconSize
            height: mode.layout.iconSize
            // at the top: the text centres on it while it's short, and grows downwards from it when open
            scale: mode.layout.appear.iconFrom + (1 - mode.layout.appear.iconFrom) * mode.iconIn
            readonly property real badgeSize: mode.layout.appBadge.size
            readonly property bool badged: mode.hasPicture && mode.hasAppIcon && picture.ready && appIcon.ready
            // where the app's icon sits: on the picture's bottom-right corner, hanging over by appBadge.overhang
            readonly property real badgeX: width - badgeSize + mode.layout.appBadge.overhang
            readonly property real badgeY: height - badgeSize + mode.layout.appBadge.overhang

            Image {
                id: picture
                anchors.fill: parent
                readonly property bool ready: status === Image.Ready
                visible: false
                source: mode.hasPicture ? mode.info.image : ""
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectCrop
                mipmap: true
            }
            // the picture, rounded concentric with the island, with a round hole where the app's icon goes
            MultiEffect {
                anchors.fill: parent
                visible: picture.ready
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
                    fillColor: Config.colors.text
                    fillRule: ShapePath.OddEvenFill
                    PathSvg {
                        path: {
                            const box = Config.roundedRectPath(iconBox.width, iconBox.height, mode.tileCorner, Config.island.cornerSmoothing);
                            if (!iconBox.badged)
                                return box;
                            const r = iconBox.badgeSize / 2 + mode.layout.appBadge.gap;
                            const cx = iconBox.badgeX + iconBox.badgeSize / 2, cy = iconBox.badgeY + iconBox.badgeSize / 2;
                            return box + " M " + (cx - r) + " " + cy + " a " + r + " " + r + " 0 1 0 " + 2 * r + " 0 a " + r + " " + r + " 0 1 0 " + -2 * r + " 0 Z";
                        }
                    }
                }
            }
            // the app's icon: whole when there's no picture, small in the picture's corner when there is
            Image {
                id: appIcon
                readonly property bool ready: status === Image.Ready
                visible: ready && (!mode.hasPicture || iconBox.badged)
                x: mode.hasPicture ? iconBox.badgeX : 0
                y: mode.hasPicture ? iconBox.badgeY : 0
                width: mode.hasPicture ? iconBox.badgeSize : iconBox.width
                height: width
                source: mode.hasAppIcon ? mode.info.icon : ""
                sourceSize.width: iconBox.width * 2
                sourceSize.height: iconBox.height * 2
                fillMode: Image.PreserveAspectFit
                mipmap: true
            }
            // nothing to show: a soft tile with a bell, the activity badges' look (red when it's urgent)
            Rectangle {
                anchors.fill: parent
                visible: !picture.ready && !appIcon.ready
                radius: mode.tileCorner
                readonly property color tint: mode.critical ? Config.colors.danger : Config.colors.text
                color: Qt.alpha(tint, Config.activity.badgeOpacity)
                Icon {
                    anchors.centerIn: parent
                    width: parent.width / 2
                    height: parent.height / 2
                    name: mode.critical ? mode.layout.criticalIcon : mode.layout.fallbackIcon
                    color: parent.tint
                }
            }
        }

        // ---- the text: (app name), title (+ its age, the close button), message ----
        Column {
            id: column
            anchors.left: iconBox.right
            anchors.leftMargin: mode.layout.spacing
            anchors.right: parent.right
            y: Math.max(0, (content.height - mode.textHeight) / 2) + (1 - mode.textIn) * mode.layout.appear.textRise
            opacity: mode.textIn
            spacing: mode.layout.lineSpacing

            StyledText {
                id: captionText
                visible: text !== ""
                width: parent.width
                elide: Text.ElideRight
                font.pixelSize: mode.layout.appNameSize
                color: Config.colors.secondary
                text: mode.caption
            }

            Item {
                id: titleRow
                width: parent.width
                height: Math.max(titleText.implicitHeight, mode.expanded ? mode.layout.closeSize : 0)
                StyledText {
                    id: titleText
                    anchors.left: parent.left
                    anchors.right: ageText.visible ? ageText.left : close.visible ? close.left : parent.right
                    anchors.rightMargin: ageText.visible || close.visible ? mode.layout.spacing : 0
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    font.pixelSize: mode.layout.summarySize
                    color: Config.colors.text
                    text: mode.title
                }
                StyledText {
                    id: ageText
                    visible: mode.showAge
                    anchors.right: close.visible ? close.left : parent.right
                    anchors.rightMargin: close.visible ? mode.layout.spacing : 0
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: mode.layout.appNameSize
                    color: Config.colors.secondary
                    text: mode.layout.minutesText.arg(mode.age)
                }
                Rectangle {
                    id: close
                    visible: opacity > 0
                    opacity: mode.expanded ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Config.motion.hoverFade
                        }
                    }
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: mode.layout.closeSize
                    height: width
                    radius: Config.corner("pill", height)
                    color: Qt.alpha(Config.colors.text, closeHover.hovered ? mode.layout.buttonHoverOpacity : mode.layout.buttonOpacity)
                    Icon {
                        anchors.centerIn: parent
                        width: parent.width * mode.layout.closeIconScale
                        height: width
                        name: mode.layout.closeIcon
                        color: Config.colors.text
                    }
                    HoverHandler {
                        id: closeHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: Sys.dismissNotification(mode.notification)
                    }
                }
            }

            StyledText {
                id: bodyText
                width: parent.width
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: mode.expanded ? mode.layout.bodyLines : 1
                font.pixelSize: mode.layout.bodySize
                font.weight: mode.layout.bodyWeight
                color: Config.colors.secondary
                textFormat: Text.StyledText
                text: mode.info ? mode.info.body : ""
                visible: text !== ""
            }

            // the notification's buttons (open only)
            Row {
                id: actionRow
                visible: mode.expanded && mode.actions.length > 0
                topPadding: mode.layout.actionGap
                spacing: mode.layout.actionSpacing
                Repeater {
                    model: mode.actions
                    delegate: Rectangle {
                        id: button
                        required property var modelData
                        width: Math.min(buttonLabel.implicitWidth + 2 * mode.layout.actionPadding, (column.width - (mode.actions.length - 1) * mode.layout.actionSpacing) / mode.actions.length)
                        height: mode.layout.actionHeight
                        radius: Config.corner("pill", height)
                        color: Qt.alpha(Config.colors.text, buttonHover.hovered ? mode.layout.buttonHoverOpacity : mode.layout.buttonOpacity)
                        StyledText {
                            id: buttonLabel
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, button.width - 2 * mode.layout.actionPadding)
                            elide: Text.ElideRight
                            font.pixelSize: mode.layout.bodySize
                            text: button.modelData.text
                        }
                        HoverHandler {
                            id: buttonHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: {
                                Sys.notificationAction(mode.notification, button.modelData.id);
                                Sys.dismissNotification(mode.notification);
                            }
                        }
                    }
                }
            }
        }
    }
}
