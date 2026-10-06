// Subsequence fuzzy scorer: every query char must appear in order.
// Bonuses for word starts and consecutive runs; 0 = no match.
.pragma library

function match(query, target) {
    if (!query) return { score: 1, idx: [] }
    const q = query.toLowerCase(), t = target.toLowerCase()
    let qi = 0, s = 0, streak = 0
    let idx = []
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
    if (qi < q.length) return { score: 0, idx: [] }
    // The greedy walk lights the first letters it meets ("orca" picks the
    // o in "Studio" before "OrcaSlicer"); when the query is there whole,
    // light that run instead.
    const at = whole(q, target)
    if (at !== -1) idx = Array.from(q, (_, i) => at + i)
    return { score: s, idx: idx }
}

// Does a word start at `at`? Start of string, after a non-alphanumeric,
// or a camelCase hump ("Slicer" in "OrcaSlicer").
function wordStart(text, at) {
    const prev = text[at - 1]
    return at === 0 || !/[a-z0-9]/i.test(prev) || (/[a-z]/.test(prev) && /[A-Z]/.test(text[at]))
}

// Where lowercase `q` sits whole in `text`: the first occurrence at a word
// start if any, else the first occurrence, else -1.
function whole(q, text) {
    const t = text.toLowerCase()
    const first = t.indexOf(q)
    for (let at = first; at !== -1; at = t.indexOf(q, at + 1))
        if (wordStart(text, at)) return at
    return first
}

// How cleanly `query` hits an item, coarser than match()'s score:
//   4  a word in the label starts with the query
//   3  a word in the sublabel does (a window's class, an app's keywords)
//   2  the query appears whole, mid-word
//   1  only as a scattered subsequence
// Ranking compares band before usage, so a popular app can't climb over
// a clean match on the strength of a loose one.
function band(query, label, sublabel) {
    if (!query) return 4
    const q = query.toLowerCase(), sub = sublabel ?? ""
    const at = whole(q, label), subAt = whole(q, sub)
    if (at !== -1 && wordStart(label, at)) return 4
    if (subAt !== -1 && wordStart(sub, subAt)) return 3
    return at !== -1 || subAt !== -1 ? 2 : 1
}

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
