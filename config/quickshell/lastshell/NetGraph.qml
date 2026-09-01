import QtQuick

// Throughput sparkline over Net.history: rx foam, tx iris, log-ish scale.
Canvas {
    id: canvas

    Connections { target: Net; function onHistoryChanged() { canvas.requestPaint() } }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const h = Net.history
        if (h.length < 2) return
        const peak = Math.max(1e4, ...h.map(s => Math.max(s[0], s[1])))
        for (const [ch, color] of [[0, Theme.foam], [1, Theme.iris]]) {
            ctx.strokeStyle = color
            ctx.lineWidth = 1.5
            ctx.beginPath()
            h.forEach((s, i) => {
                const x = i / (h.length - 1) * width
                const y = height - Math.pow(s[ch] / peak, 0.5) * (height - 2) - 1
                i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
            })
            ctx.stroke()
        }
    }
}
