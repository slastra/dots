import QtQuick

// The presence signal itself: max moving energy in the near gates over the
// last minute, on a fixed 0..100 scale, with the daemon's threshold as a
// dashed guide and its verdict as a strip along the bottom.
Sparkline {
    id: canvas
    lo: 0
    hi: 100
    bottomInset: stripH + 2   // strip plus a gap

    Connections { target: Presence; function onHistoryChanged() { canvas.repaint() } }

    readonly property real stripH: 3

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const h = Presence.history
        const pr = Presence.historyPresent
        const n = h.length
        if (n < 2) return

        if (Presence.threshold > 0) guide(ctx, Presence.threshold, Theme.textFaint)
        trace(ctx, h, Presence.present ? Theme.foam : Qt.alpha(Theme.text, 0.5), yFor(0))

        // verdict strip: foam while present, muted while away
        const w = width / n
        for (let i = 0; i < n; i++) {
            ctx.fillStyle = pr[i] ? Qt.alpha(Theme.foam, 0.8) : Qt.alpha(Theme.text, 0.18)
            ctx.fillRect(i * w, height - stripH, w + 0.5, stripH)
        }
    }
}
