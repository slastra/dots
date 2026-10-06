import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Wayland
import QtQuick
import ".."  // root module

// Notification server + top-right toast stack (replaced mako 2026-08-31).
Scope {
    id: root

    ListModel { id: toasts }
    ListModel { id: history }
    property ListModel historyModel: history

    NotificationServer {
        id: server
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: true

        onNotification: n => {
            n.tracked = true
            // closed by the sender, by expiry or by us: off both models at once
            n.closed.connect(() => root.forget(n))
            toasts.append({ notif: n })
            if (toasts.count > 5) toasts.remove(0)
            history.insert(0, { notif: n, time: Qt.formatTime(new Date(), "hh:mm AP") })
            if (history.count > 50) {
                // evicted from the center: release it server-side too, or it
                // stays tracked until the app closes it
                const old = history.get(50).notif
                history.remove(50)
                if (old?.tracked) old.dismiss()
            }
            // the desk's MQTT notification lamp; no lamp anywhere else
            if (Host.desk) {
                const lamp = Quickshell.env("HOME") + "/.config/lastshell/lamp.sh"
                Quickshell.execDetached(["bash", lamp, n.urgency === 2 ? "alert" : "info"])
            }
        }
    }

    function drop(n, dismissToo) {
        for (let i = 0; i < toasts.count; i++)
            if (toasts.get(i).notif === n) { toasts.remove(i); break }
        if (dismissToo) n.dismiss()
    }
    // A closed notification leaves both models. QML nulls a var that held a
    // destroyed object, so rows whose notif is gone or untracked go too.
    function forget(n) {
        for (const m of [toasts, history])
            for (let i = m.count - 1; i >= 0; i--) {
                const x = m.get(i).notif
                if (x === n || !x || !x.tracked) m.remove(i)
            }
    }

    // A toast was clicked. Invoke the default action (tells the app), then
    // carry the compositor to the sender's window — activation alone never
    // does: Quickshell hands out no xdg-activation token, and Firefox's
    // raise request without one produces not even an `urgent` event.
    //
    // Browsers are the hard case. A web notification carries no tab or
    // window identity (just desktop-entry=firefox), yet the browser does
    // switch to the sender's tab on ActionInvoked. So: snapshot each
    // window's active tab via tabctl, invoke, re-list, and the window whose
    // active tab changed is the one to focus — by its (now renamed) title.
    // Everything else, and any failure along the way, falls back to a
    // class match against Hyprland clients, most recently focused first.
    // Lives here (not in the toast): the toast delegate is gone by the
    // time any of these async steps return.
    function activate(n) {
        drop(n, false) // off the stack now; dismissed once the action is sent
        // Sender may have closed it already (Firefox replaces same-tag
        // notifications) between the click and this call.
        if (!n.tracked) return
        const def = n.actions?.find(a => a.identifier === "default") ?? n.actions?.[0]
        const browser = Browsers.mediatorFor(n.desktopEntry, n.appName)
        if (browser && def) {
            tabFocus.begin(browser, n, def)
            return
        }
        if (def) def.invoke()
        n.dismiss()
        focusClient(byClass([n.desktopEntry, n.appName]), 0)
    }

    QtObject {
        id: tabFocus
        property string browser
        property var notif: null
        property var action: null
        // Captured up front: the sender may close the notification (Firefox
        // does, on click) and QML nulls a var that held a destroyed object.
        property var names: []
        property bool armed: false   // action still to be sent (pre-invoke list)
        property var before: ({})    // windowId -> active tabId, pre-invoke
        property int polls: 0

        function begin(b, n, def) {
            browser = b; notif = n; action = def; armed = true; polls = 0
            names = [n.desktopEntry, n.appName]
            tabList.running = true
        }
        // Send the action exactly once, then let the sender close.
        function fire() {
            if (!armed) return
            armed = false
            if (action) action.invoke()
            if (notif) notif.dismiss()
        }
        function fallback() {
            fire()
            root.focusClient(root.byClass(names), 0)
        }
        function onList(text) {
            let tabs
            try { tabs = JSON.parse(text) } catch (e) { fallback(); return }
            const active = {}
            for (const t of tabs) if (t.active) active[t.windowId] = t
            if (armed) {
                const snap = {}
                for (const w in active) snap[w] = active[w].id
                before = snap
                fire()
                pollTimer.restart()
                return
            }
            const changed = Object.keys(active).find(w => before[w] !== active[w].id)
            if (changed !== undefined) {
                // The browser renames the window as the tab lands; give
                // Hyprland a few beats to reflect it.
                const want = active[changed].title
                const frag = Browsers.classFrag(browser)
                root.focusClient(cs => cs.find(c => c.mapped &&
                    c.class.toLowerCase().includes(frag) && Browsers.pageTitle(c.title) === want), 4)
            } else if (++polls < 5) {
                pollTimer.restart()
            } else {
                // Tab was already active in its window: nothing moved, so
                // the window is unknowable from here. Best guess by class.
                fallback()
            }
        }
    }
    Timer { id: pollTimer; interval: 120; onTriggered: tabList.running = true }
    Process {
        id: tabList
        command: ["tabctl", "--browser", tabFocus.browser, "list", "--format", "json"]
        stdout: StdioCollector { onStreamFinished: tabFocus.onList(text) }
        onExited: (code, status) => { if (code !== 0) tabFocus.fallback() }
    }

    // Focus whichever Hyprland client `pick` selects from the live list,
    // retrying `retries` times for state that is still settling.
    property var pick: null
    property int pickRetries: 0
    function focusClient(pickFn, retries) {
        pick = pickFn; pickRetries = retries
        clientsProc.running = true
    }
    // Matcher: desktop-entry / app-name against window class, exact before
    // heuristic, and among ties the most recently focused window (a Firefox
    // with three windows open used to send you to the first one listed).
    function byClass(names) {
        const cands = names.filter(s => s).map(s => s.toLowerCase())
        const norm = c => (c ?? "").toLowerCase()
        const recent = list => list.sort((a, b) => a.focusHistoryID - b.focusHistoryID)[0]
        return clients => {
            const mapped = clients.filter(c => c.mapped)
            return recent(mapped.filter(c => cands.includes(norm(c.class))))
                ?? recent(mapped.filter(c => cands.some(k =>
                    norm(c.class).includes(k) || k.includes(norm(c.class)) ||
                    norm(DesktopEntries.heuristicLookup(c.class)?.id) === k)))
        }
    }
    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let clients
                try { clients = JSON.parse(text) } catch (e) { return }
                const hit = root.pick ? root.pick(clients) : null
                if (hit) Hyprland.dispatch(`hl.dsp.focus({ window = "address:${hit.address}" })`)
                else if (root.pickRetries-- > 0) clientsRetry.restart()
            }
        }
    }
    Timer { id: clientsRetry; interval: 100; onTriggered: clientsProc.running = true }

    // Test hook: `qs -c lastshell ipc call notifs activateLatest` is a click
    // on the newest toast.
    IpcHandler {
        target: "notifs"
        function activateLatest(): void {
            if (toasts.count > 0) root.activate(toasts.get(toasts.count - 1).notif)
        }
    }

    // The window stays mapped for one remove transition after the last
    // toast leaves, so that toast slides out instead of vanishing.
    Timer { id: linger; interval: 170 }
    Connections {
        target: toasts
        function onCountChanged() { if (toasts.count === 0) linger.restart() }
    }

    PanelWindow {
        visible: toasts.count > 0 || linger.running
        color: "transparent"
        anchors { top: true; right: true }
        margins { top: Theme.barHeight + 10; right: 10 }
        implicitWidth: 380
        implicitHeight: stack.contentHeight
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        ListView {
            id: stack
            anchors.fill: parent
            interactive: false
            spacing: 8
            // NOT `model: model` — that self-references the ListView's own
            // model property and silently renders nothing
            model: toasts

            delegate: NotificationToast {
                // `notif` is the component's own required property; the model
                // role fills it — redeclaring here shadows and breaks it
                onWantsOut: dismissToo => root.drop(notif, dismissToo)
                onActivated: root.activate(notif)
            }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { property: "x"; from: 40; to: 0; duration: 180; easing.type: Easing.OutCubic }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: 170; easing.type: Easing.InCubic }
                NumberAnimation { property: "x"; to: 40; duration: 170; easing.type: Easing.InCubic }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic }
            }
        }
    }
}
