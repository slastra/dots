// Subsequence fuzzy scorer: every query char must appear in order.
// Bonuses for word starts and consecutive runs; 0 = no match.
.pragma library

function match(query, target) {
    if (!query) return { score: 1, idx: [] }
    const q = query.toLowerCase(), t = target.toLowerCase()
    let qi = 0, s = 0, streak = 0
    const idx = []
    for (let ti = 0; ti < t.length && qi < q.length; ti++) {
        if (t[ti] === q[qi]) {
            streak++
            s += 1 + streak * 2
            if (ti === 0 || t[ti - 1] === " " || t[ti - 1] === "-" || t[ti - 1] === "/")
                s += 8
            idx.push(ti)
            qi++
        } else {
            streak = 0
        }
    }
    return qi === q.length ? { score: s, idx: idx } : { score: 0, idx: [] }
}

function score(query, target) { return match(query, target).score }

// HTML for a label with its matched characters lit in `color`.
function highlight(label, idx, color) {
    if (!idx || idx.length === 0)
        return label.replace(/&/g, "&amp;").replace(/</g, "&lt;")
    const set = new Set(idx)
    let out = ""
    for (let i = 0; i < label.length; i++) {
        const c = label[i].replace(/&/g, "&amp;").replace(/</g, "&lt;")
        out += set.has(i) ? `<font color="${color}"><b>${c}</b></font>` : c
    }
    return out
}
