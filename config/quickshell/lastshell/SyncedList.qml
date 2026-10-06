import QtQuick
import "ListSync.js" as ListSync

// A keyed ListModel for chip strips. sync() reconciles `model` with a fresh
// array (rows are { key, item, gone }, see ListSync.js): rows that left are
// flagged `gone` so their chip can slide out (`present: !gone`), then
// dropped once the exit animation has had time to finish.
QtObject {
    id: root
    // dynamicRoles: `item` is a plain map (or a QObject) whatever shape the
    // first row had; without it ListModel types the role off the first insert
    readonly property ListModel model: ListModel { dynamicRoles: true }
    readonly property int count: model.count
    readonly property Timer purge: Timer {
        interval: Theme.slideDuration + 40
        onTriggered: ListSync.purge(root.model)
    }
    // `key` is a role name on the items, or a function item -> key
    function sync(items, key) {
        if (ListSync.sync(model, items, key)) purge.restart()
    }
}
