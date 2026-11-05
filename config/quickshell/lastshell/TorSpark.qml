import QtQuick

// A storm's ProbTor over its last ProbSevere scans (one per ~2 min). Fixed
// 0..35% scale so height reads as absolute risk across storms; dashed
// guides mark news.storms' tier lines (8% high, 30% urgent). One series,
// so no legend: the row it sits in names the storm.
Sparkline {
    id: canvas
    property var values: []
    property color tone: Theme.foam
    lo: 0
    hi: Math.max(35, ...(values.length ? values : [0]))
    implicitWidth: 72
    implicitHeight: 18

    onValuesChanged: repaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        guide(ctx, 8, Qt.alpha(Theme.gold, 0.35))
        guide(ctx, 30, Qt.alpha(Theme.love, 0.35))
        trace(ctx, values.length === 1 ? [values[0], values[0]] : values, tone, height)
    }
}
