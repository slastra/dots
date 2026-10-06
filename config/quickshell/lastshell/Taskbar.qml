import Quickshell
import Quickshell.Wayland
import QtQuick

// Icon-only taskbar (waybar wlr/taskbar): click activates, right-click
// fullscreens, tooltip shows the title.
//
// Toplevels go through a SyncedList so a closed window
// slides out instead of vanishing. Toplevel objects carry no stable id, so
// identity is assigned here; and Quickshell frees the object right after
// dropping it from its model, so the chip caches what it draws.
ChipRow {
    id: root
    spacing: 8

    // icon slot width; the bar narrows it when the strip would not fit
    property int slot: 40
    readonly property int count: tasks.count

    SyncedList { id: tasks }

    property var ids: new Map()
    property int nextId: 0
    function keyOf(t) {
        if (!ids.has(t)) ids.set(t, String(nextId++))
        return ids.get(t)
    }
    function resync() {
        const live = ToplevelManager.toplevels.values
        tasks.sync(live, keyOf)
        // keys for closed windows would otherwise accumulate for the session
        for (const t of Array.from(ids.keys())) if (!live.includes(t)) ids.delete(t)
    }
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.resync() }
    }
    Component.onCompleted: resync()

    Repeater {
        model: tasks.model

        Chip {
            id: task
            required property var item     // Toplevel, null once freed
            required property bool gone
            edge: "top"
            present: !gone
            active: item?.activated ?? false
            height: Theme.barHeight - 2
            contentPadding: 0   // fixed-width icon slot

            // Cached while the toplevel is alive; survives its destruction
            // for the slide-out.
            property string title: ""
            property string iconSource: ""
            readonly property string liveTitle: item?.title ?? ""
            readonly property string liveAppId: item?.appId ?? ""
            onLiveTitleChanged: if (item) title = liveTitle
            onLiveAppIdChanged: if (item) iconSource = lookupIcon(liveAppId)
            Component.onCompleted: { title = liveTitle; iconSource = lookupIcon(liveAppId) }

            function lookupIcon(appId) {
                // referencing .applications.values makes this re-evaluate
                // when the desktop-entry scan lands (the taskbar binds at
                // startup, BEFORE the scan finishes)
                void DesktopEntries.applications.values
                const e = DesktopEntries.heuristicLookup(appId)
                return e?.icon ? Quickshell.iconPath(e.icon, "image-missing") : ""
            }
            Connections {
                target: DesktopEntries.applications
                function onValuesChanged() { if (task.item) task.iconSource = task.lookupIcon(task.liveAppId) }
            }

            onClicked: item?.activate()
            onRightClicked: item?.fullscreen()

            IconChipBody { slot: root.slot; source: task.iconSource }

            ChipTip {
                owner: task
                text: task.title === "Picture in picture" ? "MPV" : task.title
            }
        }
    }
}
