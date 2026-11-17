import QtQuick

import "../services"

// Project-wide text: every label in the shell uses this. Defaults come from config.jsonc "font"
// (family, size, weight, color, roundness).
// Override color / font.pixelSize / font.weight per use when needed.
Text {
    color: Config.font.color
    font.family: Config.font.family
    font.pixelSize: Config.font.size
    font.weight: Config.font.weight
    // the font's roundness axis (Google Sans Flex rounds its letter ends; fonts without it ignore this),
    // and its weight axis: the bundled font (font.bundled) is one variable file, which Qt registers at its
    // default weight only, so font.weight alone drew it thin. Set by hand when the weight (a use may
    // override font.weight) or the roundness changes: a binding reading font.weight into the same font
    // looped
    readonly property real _roundness: Config.font.roundness
    function _syncAxes() {
        const a = font.variableAxes || {};
        if (a.ROND !== _roundness || a.wght !== font.weight)
            font.variableAxes = {
                "ROND": _roundness,
                "wght": font.weight
            };
    }
    on_RoundnessChanged: _syncAxes()
    onFontChanged: _syncAxes()
    Component.onCompleted: _syncAxes()
}
