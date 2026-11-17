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
    // the font's roundness axis (Google Sans Flex rounds its letter ends; fonts without it ignore this)
    font.variableAxes: ({
            "ROND": Config.font.roundness
        })
}
