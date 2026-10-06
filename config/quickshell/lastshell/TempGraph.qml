import QtQuick

// Package-temperature sparkline over SysStat.tempHistory. Fixed 30..90°C
// scale (same span as the chip's thermometer) rather than NetGraph's
// peak-relative one, so height reads as absolute heat; dashed guides mark
// the 70° warning and 80° critical lines, and the trace takes the current
// reading's tone.
Sparkline {
    id: canvas
    lo: 30
    hi: 90

    Connections { target: SysStat; function onTempHistoryChanged() { canvas.repaint() } }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        guide(ctx, 70, Qt.alpha(Theme.gold, 0.35))
        guide(ctx, 80, Qt.alpha(Theme.love, 0.35))
        trace(ctx, SysStat.tempHistory, Theme.level(SysStat.tempC, 70, 80), height)
    }
}
