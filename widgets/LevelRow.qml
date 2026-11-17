import QtQuick

import "../services"

// A volume or brightness row: the icon at the left (Speaker, which mutes on click, or the sun that turns
// with the level), the level bar (LevelSlider: drag, scroll, bump at the ends), the value at the right
// (fixed width, the widest possible value, so the bar doesn't jitter). One piece for the volume and
// brightness pop-ups and quick settings; each sets its sizes. Changing the level goes through Sys and keeps
// the pop-up up (Activity.feedback, which does nothing while quick settings is shown).
Item {
    id: row

    property string kind: "volume"          // "volume" | "brightness"
    property bool live: true                // on screen: bounce when a key hits the limit (Activity.bumped)
    property bool starting: false           // about to be on screen (fading in): hold the bounce until live
    property real iconSize: Config.activity.glyphSize
    property real gap: Config.activity.spacing
    property bool showValue: true
    property real valueSize: Config.activity.titleSize
    property color valueColor: Config.colors.text

    readonly property bool isVolume: kind === "volume"
    readonly property var cfg: isVolume ? Config.volume : Config.brightness
    readonly property real level: isVolume ? Sys.audio.volume : Sys.brightness.level
    readonly property bool muted: isVolume && Sys.audio.muted
    readonly property real maximum: isVolume ? Config.volume.max : 1

    implicitHeight: Math.max(iconSize, Config.slider.height)

    property int _heldBump: 0
    Connections {
        target: Activity
        enabled: row.live || row.starting
        function onBumped(kind, direction) {
            if (kind !== row.kind)
                return;
            if (row.live)
                slider.bump(direction);
            else
                row._heldBump = direction;
        }
    }
    onLiveChanged: {
        if (live && _heldBump !== 0)
            slider.bump(_heldBump);
        _heldBump = 0;
    }

    Item {
        id: glyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: row.iconSize
        height: row.iconSize

        // like the Wi-Fi icon: the full speaker dimmed, the real level bright on top
        Speaker {
            anchors.fill: parent
            visible: row.isVolume
            level: row.level
            muted: row.muted
        }
        Icon {
            anchors.fill: parent
            visible: !row.isVolume
            name: row.isVolume ? "" : row.cfg.icons[Math.min(row.cfg.icons.length - 1, Math.floor(row.level * row.cfg.icons.length))]
            color: Config.colors.text
            rotation: row.isVolume ? 0 : slider.shown * row.cfg.iconTurn
        }
        HoverHandler {
            enabled: row.isVolume
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: row.isVolume
            onTapped: {
                Sys.toggleMute();
                Activity.feedback(row.kind);
            }
        }
    }

    LevelSlider {
        id: slider
        anchors.left: glyph.right
        anchors.leftMargin: row.gap
        anchors.right: row.showValue ? value.left : parent.right
        anchors.rightMargin: row.showValue ? row.gap : 0
        anchors.verticalCenter: parent.verticalCenter
        value: row.level
        maximum: row.maximum
        step: row.cfg.step
        dimmed: row.muted
        onMoved: v => {
            if (row.isVolume)
                Sys.setVolume(v);
            else
                Sys.setBrightness(v);
            Activity.feedback(row.kind);
        }
    }

    TextMetrics {
        id: widest
        font: value.font
        text: Math.round(row.maximum * 100) + "%"
    }
    StyledText {
        id: value
        visible: row.showValue
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: widest.advanceWidth
        horizontalAlignment: Text.AlignRight
        font.pixelSize: row.valueSize
        font.features: {
            "tnum": 1
        }
        color: row.valueColor
        opacity: row.muted ? Config.slider.dimmedOpacity : 1
        text: Math.round(row.level * 100) + "%"
    }
}
