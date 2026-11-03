import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module

// The polkit prompt: lastshell is the session's authentication agent
// (PolkitAgent lives in Overlays), and this is its face. Open while a
// request is active; esc or a click outside cancels the request.
//
// pam_faillock locks the account after `deny` failures inside
// `fail_interval`, and a cancelled conversation counts as one. That lock
// then refuses sudo and the screen locker too, so the dialog shows the
// attempts left and the lock itself instead of letting it land silently.
Overlay {
    id: root

    required property var agent
    readonly property var flow: agent.flow

    cardWidth: 520
    contentPadding: 2
    open: agent.isActive

    property string password: ""
    property bool capsLock: false
    property bool wrong: false   // the last attempt failed; cleared on typing
    readonly property bool busy: !!flow && !flow.isResponseRequired

    // pam_faillock's view of this user; refreshed per request and per failure
    readonly property string user: Quickshell.env("USER")
    property int deny: 3
    property int failInterval: 900
    property int unlockTime: 600
    property var failures: []   // epoch seconds of valid failures
    readonly property int recent: {
        const now = clock.now
        return failures.filter(t => now - t < failInterval).length
    }
    readonly property int lockedUntil: recent >= deny && unlockTime > 0
        ? Math.max(...failures) + unlockTime : 0
    readonly property bool locked: lockedUntil > clock.now
    readonly property int triesLeft: Math.max(0, deny - recent)

    // Apps whose own unlock goes through polkit: say which password this
    // is, since the app has a password of its own the user may reach for.
    readonly property var hints: ({
        "com.1password.1Password.unlock": "your login password, not the 1Password master password"
    })
    readonly property string hint: flow ? (hints[flow.actionId] ?? "") : ""

    // Esc and click-away cancel the request; the dialog closes when the
    // agent drops it (open is bound to agent.isActive).
    function dismiss() { if (flow && !flow.isCompleted) flow.cancelAuthenticationRequest() }
    function toggle() {}

    function submit() {
        if (!flow || busy || !password) return
        flow.submit(password)
        password = ""
    }

    onFlowChanged: {
        password = ""; wrong = false
        if (flow) tally.running = true
    }

    Connections {
        target: root.flow
        function onAuthenticationFailed() {
            root.wrong = true
            root.jolt()
            tally.running = true
        }
    }

    QtObject {
        id: clock
        property int now: Date.now() / 1000
    }
    Timer {
        interval: 1000; repeat: true; running: root.open
        onTriggered: clock.now = Date.now() / 1000
    }

    Process {
        id: limits
        running: true
        command: ["cat", "/etc/security/faillock.conf"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const m = line.match(/^\s*(deny|fail_interval|unlock_time)\s*=\s*(\d+)/)
                    if (!m) continue
                    const v = parseInt(m[2])
                    if (m[1] === "deny") root.deny = v
                    else if (m[1] === "fail_interval") root.failInterval = v
                    else root.unlockTime = v
                }
            }
        }
    }
    Process {
        id: tally
        command: ["faillock", "--user", root.user]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const m = line.match(/^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d)\s.*\sV\s*$/)
                    if (m) out.push(new Date(`${m[1]}T${m[2]}`).getTime() / 1000)
                }
                clock.now = Date.now() / 1000
                root.failures = out
            }
        }
    }

    function fmtTime(epoch) {
        return Qt.formatTime(new Date(epoch * 1000), "hh:mm")
    }

    Column {
        width: parent.width
        focus: true

        Keys.onPressed: event => {
            const k = event.key, ctrl = event.modifiers & Qt.ControlModifier
            if (k === Qt.Key_Escape) root.dismiss()
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.submit()
            else if (k === Qt.Key_Backspace) root.password = root.password.slice(0, -1)
            else if (ctrl && k === Qt.Key_U) root.password = ""
            else if ((k === Qt.Key_Tab || k === Qt.Key_Backtab) && root.flow?.identities.length > 1) {
                const ids = root.flow.identities, n = ids.length
                const i = ids.indexOf(root.flow.selectedIdentity)
                root.password = ""
                root.flow.selectedIdentity = ids[(i + (k === Qt.Key_Tab ? 1 : n - 1)) % n]
            }
            else if (event.text && event.text >= " " && !ctrl) {
                if (/[a-z]/i.test(event.text))
                    root.capsLock = (event.text === event.text.toUpperCase()) !== !!(event.modifiers & Qt.ShiftModifier)
                root.password += event.text
                root.wrong = false
            }
            else return
            event.accepted = true
        }

        ModalHeader {
            icon: "shield-check"; title: "Authenticate"; showQuery: false
            PopText {
                anchors.right: parent.right; anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                size: 13; color: Theme.textFaint
                text: root.flow?.selectedIdentity?.displayName ?? root.user
            }
        }

        // what is asking, and for which password
        Column {
            x: 18
            width: parent.width - 36
            topPadding: 16
            bottomPadding: 14
            spacing: 6

            PopText {
                width: parent.width
                size: 15
                wrapMode: Text.Wrap
                text: root.flow?.message ?? ""
            }
            PopText {
                visible: root.hint !== ""
                width: parent.width
                size: 13; color: Theme.gold
                wrapMode: Text.Wrap
                text: root.hint
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.seam }

        // the secret: the greeter's field treatment
        Rectangle {
            width: parent.width; height: 54
            color: Theme.overlay

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 18; spacing: 12
                LucideIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 18
                    name: root.locked ? "shield-alert" : root.busy ? "shield-check" : "key-round"
                    color: root.locked || root.wrong ? Theme.love : root.busy ? Theme.foam : Theme.rose
                }
                LucideIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-right"; font.pixelSize: 14; color: Theme.textFaint
                }
                Item { // typed value, caret at its end, ghost prompt after the caret
                    anchors.verticalCenter: parent.verticalCenter
                    height: 22
                    width: value.implicitWidth + 4 + (ghost.visible ? ghost.implicitWidth + 8 : 0) + (pulse.visible ? 14 : 0)
                    PopText {
                        id: value
                        anchors.verticalCenter: parent.verticalCenter
                        size: 17
                        color: root.busy ? Theme.textMuted : Theme.text
                        text: root.busy ? "checking"
                            : root.flow?.responseVisible ? root.password : "●".repeat(root.password.length)
                    }
                    Rectangle {
                        id: caret
                        x: value.implicitWidth + (value.text ? 2 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2; height: 22; color: Theme.rose
                        visible: !root.busy
                        SequentialAnimation on opacity {
                            running: root.open && caret.visible; loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: Theme.blinkDuration }
                            NumberAnimation { to: 1; duration: Theme.blinkDuration }
                        }
                    }
                    PopText { // the prompt as a ghost: it never captures the caret
                        id: ghost
                        x: caret.x + 8
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.busy && !root.password
                        size: 17; color: Qt.alpha(Theme.text, 0.3)
                        text: (root.flow?.inputPrompt ?? "").replace(/:\s*$/, "").trim().toLowerCase() || "password"
                    }
                    Rectangle { // a breathing foam dot while PAM works
                        id: pulse
                        x: value.implicitWidth + 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4; color: Theme.foam
                        visible: root.busy
                        SequentialAnimation on scale {
                            running: pulse.visible; loops: Animation.Infinite
                            NumberAnimation { to: 0.5; duration: 450; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
            PopText { // caps lock, right-aligned in the field
                anchors.right: parent.right; anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                visible: root.capsLock && !!root.password
                size: 12; color: Theme.gold
                text: "caps lock"
            }
        }

        // status: PAM's own words, then the lockout arithmetic
        Item {
            width: parent.width
            height: status.text ? status.implicitHeight + 24 : 0
            PopText {
                id: status
                x: 18; y: 12
                width: parent.width - 36
                size: 13
                wrapMode: Text.Wrap
                readonly property string pam: root.flow?.supplementaryMessage ?? ""
                color: root.locked || root.wrong || root.flow?.supplementaryIsError ? Theme.love
                     : root.triesLeft === 1 ? Theme.gold : Theme.textMuted
                text: root.locked
                        ? `Locked by too many failures until ${root.fmtTime(root.lockedUntil)}. Even the right password is refused until then.`
                    : [
                        root.wrong ? "Wrong password." : pam,
                        root.recent > 0 && root.triesLeft > 0
                            ? `${root.triesLeft} ${root.triesLeft === 1 ? "try" : "tries"} left before a ${Math.round(root.unlockTime / 60)} min lockout. Cancelling counts as one.`
                            : ""
                      ].filter(s => s).join(" ")
            }
        }

        ModalFooter {
            hint: "enter submit   esc cancel" + (root.flow?.identities.length > 1 ? "   tab user" : "")
            count: root.flow?.actionId ?? ""
        }
    }
}
