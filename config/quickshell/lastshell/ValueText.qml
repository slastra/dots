import QtQuick

// Chip value text. ShureTechMono's digits and caps leave the descender
// space unused, so a vertically-centered em box carries its ink high;
// +0.75 logical px puts the INK on the icons' measured center line
// (text ran 18.0 device, icons 19.0 — bar-m2 measurement, 2026-08-31).
//
// Placed by BASELINE, computed from the primary font's metrics, rather than
// by centring the line box: a glyph from a fallback font (Claude's ◐ spinner
// in a window title comes from Noto Sans Mono) grows the line box and would
// drop the whole line 1-2 px. The offset is the old centring spelled out
// (Text rounds its line box up to whole pixels, hence the ceil), so all-
// ShureTechMono text lands exactly where it always did.
Text {
    id: root
    anchors.baseline: parent.verticalCenter
    anchors.baselineOffset: 0.75 + metrics.ascent - Math.ceil(metrics.height) / 2
    font.family: Theme.fontFamily
    font.pixelSize: 16
    color: Theme.text
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

    FontMetrics { id: metrics; font: root.font }
}
