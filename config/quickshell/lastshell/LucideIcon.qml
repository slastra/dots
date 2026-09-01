import QtQuick

// One lucide glyph, tinted like text. Sized slightly under the text size —
// lucide draws to the full em square and reads large beside ShureTechMono.
Text {
    property string name
    font.family: Lucide.family
    font.pixelSize: 15
    color: Theme.text
    text: Lucide.icon(name)
    verticalAlignment: Text.AlignVCenter
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
}
