pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

import "services"
import "widgets"

// Rounded screen corners (config screenCorners), like a Mac display: four tiny click-through overlay
// windows, one per corner of the screen, each painting the area outside a rounded corner (smoothed like the island's: screenCorners.smoothing). Above
// everything (fullscreen apps too); they reserve no space and take no input.
Scope {
    id: corners

    required property ShellScreen modelData

    // An inline component can't see the ids of this file: the screen is passed in by each Corner below.
    component Corner: PanelWindow {
        id: win
        // rotation that turns the top-left drawing into this corner (multiples of 90 degrees)
        property int turn: 0
        readonly property real size: Config.screenCorner.p

        visible: Config.screenCorners.enabled
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-corners"
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: size
        implicitHeight: size
        color: "transparent"
        // no input region: clicks and hover go to whatever is below
        mask: Region {}

        CornerShape {
            size: win.size
            rotation: win.turn
        }
    }

    Corner {
        screen: corners.modelData
        anchors.top: true
        anchors.left: true
    }
    Corner {
        screen: corners.modelData
        anchors.top: true
        anchors.right: true
        turn: 90
    }
    Corner {
        screen: corners.modelData
        anchors.bottom: true
        anchors.right: true
        turn: 180
    }
    Corner {
        screen: corners.modelData
        anchors.bottom: true
        anchors.left: true
        turn: 270
    }
}
