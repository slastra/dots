import QtQuick

// Base for the popout sparklines (net, temperature, presence): a Canvas
// that only repaints while `live` (bind it to the owning Popout's
// visible), with the shared drawing helpers. Subclasses set lo/hi and
// override onPaint using them.
Canvas {
    id: canvas

    property bool live: true
    property real lo: 0
    property real hi: 1
    property real bottomInset: 0   // room kept under the trace (a verdict strip)

    onLiveChanged: if (live) requestPaint()
    function repaint() { if (live) requestPaint() }

    function xFor(i, n) { return i / (n - 1) * width }
    // fixed-scale y: lo one pixel above the bottom (or the inset), hi one below the top
    function yFor(v) {
        const frac = Math.max(0, Math.min(1, (v - lo) / (hi - lo)))
        return (height - 1 - bottomInset) - frac * (height - 2 - bottomInset)
    }
    // dashed horizontal rule at a value
    function guide(ctx, v, color) {
        const y = Math.round(yFor(v)) + 0.5
        ctx.lineWidth = 1
        ctx.setLineDash([3, 3])
        ctx.strokeStyle = color
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
        ctx.setLineDash([])
    }
    // soft fill down to baseY, then the 1.5 px trace
    function trace(ctx, values, tone, baseY) {
        const n = values.length
        if (n < 2) return
        ctx.beginPath()
        ctx.moveTo(xFor(0, n), baseY)
        values.forEach((v, i) => ctx.lineTo(xFor(i, n), yFor(v)))
        ctx.lineTo(xFor(n - 1, n), baseY)
        ctx.closePath()
        ctx.fillStyle = Qt.alpha(tone, 0.12)
        ctx.fill()

        ctx.strokeStyle = tone
        ctx.lineWidth = 1.5
        ctx.lineJoin = "round"
        ctx.beginPath()
        values.forEach((v, i) => i === 0 ? ctx.moveTo(xFor(i, n), yFor(v)) : ctx.lineTo(xFor(i, n), yFor(v)))
        ctx.stroke()
    }
}
