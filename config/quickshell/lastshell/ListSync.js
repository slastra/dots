.pragma library

// Reconcile a ListModel with a fresh array without rebuilding it.
// Rows are { key, item, gone }: existing keys are updated in place (and
// moved if their order changed), new keys inserted, and keys that left
// are flagged `gone` rather than removed so their chip can slide out.
// Returns true when anything was flagged; the caller then runs purge()
// once the exit animation has had time to finish.
// `keyField` is a role name, or a function returning a key for an item.
function sync(model, items, keyField) {
    const keyOf = typeof keyField === "function" ? keyField : it => String(it[keyField])
    const want = new Set(items.map(keyOf))
    let anyGone = false
    for (let i = 0; i < model.count; i++) {
        const row = model.get(i)
        if (!want.has(row.key)) {
            if (!row.gone) model.setProperty(i, "gone", true)
            anyGone = true
        }
    }
    let pos = 0 // model index the next live item belongs at
    items.forEach(it => {
        const key = keyOf(it)
        while (pos < model.count && model.get(pos).gone) pos++
        let cur = -1
        for (let i = 0; i < model.count; i++)
            if (model.get(i).key === key) { cur = i; break }
        if (cur < 0) {
            model.insert(pos, { key: key, item: it, gone: false })
        } else {
            // A row before pos can only be a gone one the skip above passed
            // over, now coming back (a workspace refilled mid slide-out).
            // Taking it out shifts pos down one; moving it to pos itself ran
            // past the end ("move: out of range"), the revive never landed,
            // and purge dropped a chip that should be showing.
            if (cur < pos) {
                pos--
                if (cur !== pos) model.move(cur, pos, 1)
            } else if (cur > pos) {
                model.move(cur, pos, 1)
            }
            model.setProperty(pos, "item", it)
            if (model.get(pos).gone) model.setProperty(pos, "gone", false)
        }
        pos++
    })
    return anyGone
}

function purge(model) {
    for (let i = model.count - 1; i >= 0; i--)
        if (model.get(i).gone) model.remove(i)
}
