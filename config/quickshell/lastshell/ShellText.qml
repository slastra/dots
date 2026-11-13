import QtQuick

// Every piece of text in the shell: the shell font at a scaled size, and
// one rule for where it sits. A single line is placed by its INK, not its
// line box: the middle of its capitals and digits lands on the middle of
// the line box, less the icons' lift, so a label centered beside an icon
// shares its center line in any font and at any display scale. Centering
// the line box alone does not do that: each font leaves different room
// above and below its letters (ShureTechMono rode high, Geist Mono low).
//
// The shift is a transform, so it moves the glyphs and nothing else:
// layout, heights and anchors are exactly what they were. It reads the
// real baseline, so a glyph from a fallback font (Claude's ◐ spinner comes
// from Noto Sans Mono) that grows the line box does not drop the line.
// Wrapped text is left alone. An item with its own transform must chain
// `inkShift` in, as WindowTitle does.
Text {
    id: root
    property int size: 13
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fs(size)
    color: Theme.text
    // Qt snaps a centered item to a whole pixel, which would move the ink
    // by up to half a pixel depending on whether the line box is odd or even
    anchors.alignWhenCentered: false

    readonly property real inkShift: {
        if (lineCount !== 1) return 0
        const slack = height - contentHeight - topPadding - bottomPadding
        const aligned = verticalAlignment === Text.AlignVCenter ? slack / 2
                      : verticalAlignment === Text.AlignBottom ? slack : 0
        const baseline = baselineOffset - aligned - topPadding   // within the line box
        return (contentHeight / 2 - Theme.iconLift) - (baseline - font.pixelSize * Theme.capRatio / 2)
    }
    transform: Translate { y: root.inkShift }
}
