import QtQuick

import "../services"

// Project-wide text: every label in the shell uses this. Defaults come from config.jsonc "font"
// (family, size, weight, roundness); the color is the surface's text color (palette.windowText: white in
// the bar and the notch, the light / dark theme's in the dropdowns and the notification cards, see
// Config.theme). Override color / font.pixelSize / font.weight per use when needed.
Text {
    color: palette.windowText
    font.family: Config.font.family
    font.pixelSize: Config.font.size
    font.weight: Config.font.weight
    // the font's variable axes (Config.axes: roundness, weight, optical size). The bundled font is one
    // variable file, which Qt registers at its default weight only, so font.weight alone drew it thin. Set
    // by hand when the size, the weight or the settings change: a binding reading font.weight into the
    // same font looped
    readonly property var _axesFor: Config.font
    function _syncAxes() {
        const want = Config.axes(font.pixelSize, font.weight);
        const a = font.variableAxes || {};
        if (Object.keys(want).some(k => a[k] !== want[k]) || Object.keys(a).length !== Object.keys(want).length)
            font.variableAxes = want;
    }
    on_AxesForChanged: _syncAxes()
    onFontChanged: _syncAxes()
    Component.onCompleted: _syncAxes()
}
