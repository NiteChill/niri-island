import QtQuick

import "../services"

// Horizontal level bar (volume, brightness): a rounded track with the level filled in,
// and anything past 100 % (when `maximum` > 1) in `overColor`. Drag, click or scroll to change it.
// bump(direction): pushed past the end, the bar grows a little that way and springs back (its real width
// changes: the ends stay round, nothing is squashed).
// `released` after a press or drag (not the wheel). Settings: config.jsonc slider.
Item {
    id: slider

    // API
    property real value: 0          // 0 - maximum
    property real maximum: 1
    property real step: 0           // one scroll notch
    property bool dimmed: false     // e.g. muted
    property color overColor: Config.colors.danger
    property bool animated: true    // spring to a new value (false: show it at once, e.g. a moving position)
    readonly property bool pressed: drag.pressed
    signal moved(real value)
    signal released

    readonly property var cfg: Config.slider
    implicitHeight: cfg.height

    // ---- bump ----
    property real stretch: 0        // px added toward stretchDir
    property int stretchDir: 1
    function bump(direction) {
        stretchDir = direction;
        bumpAnim.stop();
        bumpBack.stop();
        const s = Config.spring(cfg.bump);
        bumpBack.spring = s.spring;
        bumpBack.damping = s.damping;
        bumpAnim.start();
    }
    // stretch out, then spring back
    // (a SpringAnimation can't sit in a SequentialAnimation: it has no fixed duration, so it would jump)
    NumberAnimation {
        id: bumpAnim
        target: slider
        property: "stretch"
        to: slider.cfg.bumpStretch
        duration: slider.cfg.bumpIn
        easing.type: Easing.OutCubic
        onFinished: bumpBack.start()
    }
    SpringAnimation {
        id: bumpBack
        target: slider
        property: "stretch"
        to: 0
        epsilon: 0.05
    }

    // ---- shown level (springs to the value, follows the pointer exactly while dragging) ----
    readonly property real fraction: maximum > 0 ? Math.max(0, Math.min(1, value / maximum)) : 0
    property real shown: fraction
    Behavior on shown {
        enabled: slider.animated && !drag.pressed
        SpringAnimation {
            spring: Config.spring(slider.cfg.follow).spring
            damping: Config.spring(slider.cfg.follow).damping
            epsilon: 0.001
        }
    }

    // the corner style's pill corner (island.shape, see Config.corner)
    readonly property real corner: Config.corner("pill", height)

    // the drawn bar: the slider's width plus the bump, grown toward the push
    Item {
        id: body
        x: slider.stretchDir > 0 ? 0 : -slider.stretch
        width: slider.width + slider.stretch
        height: slider.height

        // track
        Rectangle {
            anchors.fill: parent
            radius: slider.corner
            color: Config.colors.text
            opacity: slider.cfg.trackOpacity
        }
        // the fill, dimmed as one piece (muted): fading each part on its own let the red under the white
        // show through it. The layer exists only while dimmed (or fading).
        Item {
            anchors.fill: parent
            opacity: slider.dimmed ? slider.cfg.dimmedOpacity : 1
            layer.enabled: opacity < 1
            Behavior on opacity {
                NumberAnimation {
                    duration: Config.motion.colorFade
                }
            }
            // past 100 %: drawn under the normal fill, so only the extra part shows; muted, plain white like
            // the rest (the red says "louder than normal", not something to see while silent)
            Rectangle {
                visible: slider.maximum > 1
                width: slider.shown * body.width
                height: parent.height
                radius: Math.min(slider.corner, width / 2)
                color: slider.dimmed ? Config.colors.text : slider.overColor
                Behavior on color {
                    ColorAnimation {
                        duration: Config.motion.colorFade
                    }
                }
            }
            // level up to 100 %
            Rectangle {
                width: Math.min(slider.shown, slider.maximum > 1 ? 1 / slider.maximum : 1) * body.width
                height: parent.height
                radius: Math.min(slider.corner, width / 2)
                color: Config.colors.text
            }
        }
    }

    // input: a taller hit area than the thin bar
    MouseArea {
        id: drag
        anchors.fill: parent
        anchors.topMargin: -slider.cfg.hitMargin
        anchors.bottomMargin: -slider.cfg.hitMargin
        cursorShape: Qt.PointingHandCursor
        function set(mx) {
            slider.moved(Math.max(0, Math.min(1, mx / slider.width)) * slider.maximum);
        }
        onPressed: mouse => set(mouse.x)
        onReleased: slider.released()
        onPositionChanged: mouse => {
            if (pressed)
                set(mouse.x);
        }
        onWheel: wheel => {
            const dir = wheel.angleDelta.y > 0 || wheel.angleDelta.x < 0 ? 1 : -1;
            slider.moved(Math.max(0, Math.min(slider.maximum, slider.value + dir * slider.step)));
        }
    }
}
