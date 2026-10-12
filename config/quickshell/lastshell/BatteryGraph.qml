import QtQuick

// Battery history over the last `span` seconds, from UPower's own history
// files (see BatteryChip), so it reaches back past a shell restart. x is
// time, not sample index: UPower logs charge only when the percentage moves.
//   mode "charge"  fixed 0..100 %, dashed 20 % / 10 % guides, gold while
//                  discharging and foam while charging
//   mode "rate"    watts, peak-relative, averaged into `buckets` columns;
//                  a gap longer than 10 min (suspend, off) breaks the line
// Samples are [unix seconds, value, state] with state "charging" |
// "discharging" | anything else.
Sparkline {
    id: canvas

    property string mode: "charge"
    property var samples: []
    property real span: 12 * 3600
    property real now: Date.now() / 1000
    property real current: 0          // live value, carried to the right edge
    property bool charging: false
    property int buckets: 96

    // the scale the rate graph settled on, for the caption
    property real peak: 1

    lo: 0
    hi: mode === "charge" ? 100 : peak

    onSamplesChanged: repaint()
    onSpanChanged: repaint()
    onCurrentChanged: repaint()

    function xAt(t) { return (t - (now - span)) / span * width }
    function tone(state) { return state === "charging" ? Theme.foam : Theme.gold }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        mode === "charge" ? paintCharge(ctx) : paintRate(ctx)
    }

    function paintCharge(ctx) {
        guide(ctx, 20, Qt.alpha(Theme.gold, 0.35))
        guide(ctx, 10, Qt.alpha(Theme.love, 0.35))
        const start = now - span
        // the last sample before the window anchors the left edge
        let pts = []
        for (const s of samples) {
            if (s[0] < start) pts = [[start, s[1], s[2]]]
            else pts.push(s)
        }
        pts.push([now, current, charging ? "charging" : "discharging"])
        if (pts.length < 2) return
        // one segment per state run, so charging reads in its own colour
        for (let i = 1; i < pts.length; i++) {
            const a = pts[i - 1], b = pts[i]
            const col = tone(b[2])
            ctx.beginPath()
            ctx.moveTo(xAt(a[0]), height)
            ctx.lineTo(xAt(a[0]), yFor(a[1]))
            ctx.lineTo(xAt(b[0]), yFor(b[1]))
            ctx.lineTo(xAt(b[0]), height)
            ctx.closePath()
            ctx.fillStyle = Qt.alpha(col, 0.12)
            ctx.fill()
            ctx.strokeStyle = col
            ctx.lineWidth = 1.5
            ctx.lineJoin = "round"
            ctx.beginPath()
            ctx.moveTo(xAt(a[0]), yFor(a[1]))
            ctx.lineTo(xAt(b[0]), yFor(b[1]))
            ctx.stroke()
        }
    }

    function paintRate(ctx) {
        const start = now - span, w = span / buckets
        const sum = new Array(buckets).fill(0), n = new Array(buckets).fill(0)
        const chg = new Array(buckets).fill(0)
        for (const s of samples) {
            if (s[0] < start || s[1] <= 0) continue  // UPower logs 0 W at state changes
            const i = Math.min(buckets - 1, Math.floor((s[0] - start) / w))
            sum[i] += s[1]; n[i]++
            if (s[2] === "charging") chg[i]++
        }
        const avg = sum.map((v, i) => n[i] ? v / n[i] : -1)
        peak = Math.max(5, ...avg)
        // bucket centres; empty buckets break the line (gaps under 10 min
        // are bridged: UPower writes every 30 s, buckets are wider)
        const bridge = Math.ceil(600 / w)
        let run = [], miss = 0
        const flush = () => {
            if (run.length > 1) {
                for (let k = 1; k < run.length; k++) {
                    const a = run[k - 1], b = run[k]
                    ctx.strokeStyle = tone(b.state)
                    ctx.lineWidth = 1.5
                    ctx.beginPath()
                    ctx.moveTo(a.x, yFor(a.v)); ctx.lineTo(b.x, yFor(b.v))
                    ctx.stroke()
                }
            }
            run = []
        }
        for (let i = 0; i < buckets; i++) {
            if (avg[i] < 0) { if (++miss > bridge) flush(); continue }
            miss = 0
            run.push({ x: (i + 0.5) / buckets * width, v: avg[i],
                       state: chg[i] * 2 > n[i] ? "charging" : "discharging" })
        }
        flush()
    }
}
