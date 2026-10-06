import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import QtQuick
import ".."  // lastshell root module: Theme, Chip, LucideIcon, ValueText

// lastshell's ninth modal: the login screen. Same tab chips on the screen
// edges, same card chrome, same header idiom (identity icon › chevron ›
// text + rose caret), same gliding rose outline for picking a session.
// Speaks greetd through Quickshell.Services.Greetd; with no greetd socket
// it runs as a demo (password "pass" succeeds) so it can be previewed in a
// nested compositor. Entry point is ../greeter.qml so the lastshell root
// module (Theme, Chip, LucideIcon, ValueText) is in scope.
Scope {
    id: root

    FontLoader { // bundled: the greeter user cannot see ~/.local/share/fonts
        source: Qt.resolvedUrl("assets/lucide.ttf")
        onStatusChanged: if (status !== FontLoader.Loading) console.info("lucide font:", status === FontLoader.Ready ? "ready as " + name : "FAILED " + source)
    }

    readonly property bool demo: !Greetd.available
    readonly property string stateFile:
        Quickshell.env("LASTSHELL_GREETER_STATE") || "/var/lib/lastshell-greeter/state.json"
    readonly property string bg: "#13111e"   // = hyprland.lua misc.background_color

    property var users: []
    property var sessions: []
    property int sessionIndex: 0
    property int userIndex: 0
    property string user: ""
    property string hostname: "desk"

    // phase: "user" editing the name · "password" typing · "busy" greetd is
    // thinking · "launch" handing over
    property string phase: "password"
    property string password: ""
    property string prompt: "password"
    property bool echo: false
    property string message: ""
    property bool messageIsError: false
    property bool capsLock: false   // inferred: a letter arriving in the wrong case for the Shift state
    signal failed()

    // ── data ─────────────────────────────────────────────────────────────
    FileView { id: hostView; path: "/etc/hostname"; blockLoading: true }
    FileView { id: stateView; path: root.stateFile; blockLoading: true }
    property var saved: ({})
    Component.onCompleted: {
        const h = hostView.text().trim(); if (h) hostname = h
        try { saved = JSON.parse(stateView.text()) } catch (e) { saved = {} }
    }

    Process {
        command: ["sh", "-c", "getent passwd | awk -F: '$3>=1000 && $3<65000 {print $3, $1}' | sort -n | cut -d' ' -f2"]
        running: true
        stdout: StdioCollector { onStreamFinished: {
            root.users = text.trim().split("\n").filter(u => u)
            root.applyState()
        } }
    }
    Process {
        command: [Qt.resolvedUrl("sessions.sh").toString().replace(/^file:\/\//, "")]
        running: true
        stdout: StdioCollector { onStreamFinished: {
            root.sessions = text.trim().split("\n").filter(l => l).map(l => {
                const p = l.split("\t")
                return { name: p[0], exec: p[1], desktop: p[2], id: p[3] }
            })
            if (!root.sessions.length)
                root.sessions = [{ name: "Hyprland", exec: "/usr/bin/start-hyprland", desktop: "Hyprland", id: "hyprland" }]
            root.applyState()
        } }
    }
    function applyState() {
        if (!user && users.length) {
            userIndex = Math.max(0, users.indexOf(saved.user ?? ""))
            user = users[userIndex]
        }
        if (sessions.length) {
            let i = sessions.findIndex(s => s.id === saved.session)
            if (i < 0) i = sessions.findIndex(s => s.id === "hyprland")
            sessionIndex = Math.max(0, i)
        }
    }
    Process { id: saveProc }
    function saveState() {
        const json = JSON.stringify({ user: user, session: sessions[sessionIndex]?.id ?? "" })
        saveProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "save", stateFile, json]
        saveProc.running = true
    }

    // ── auth flow ────────────────────────────────────────────────────────
    function submit() {
        if (phase === "user") {
            if (user) { phase = "password"; password = ""; message = "" }
            return
        }
        if (phase !== "password" || !password) return
        message = ""; phase = "busy"
        if (demo) { demoTimer.start(); return }
        if (Greetd.state === GreetdState.Inactive) Greetd.createSession(user)
        else { Greetd.respond(password); password = "" }
    }
    Timer { id: demoTimer; interval: 900; onTriggered: root.password === "pass" ? root.launch() : root.fail("Authentication failed") }

    function fail(msg) {
        message = msg; messageIsError = true
        password = ""; prompt = "password"; echo = false
        phase = "password"; failed()
    }
    function launch() {
        saveState()
        const s = sessions[sessionIndex]
        phase = "launch"; message = ""
        if (demo) { message = "demo · would start " + s.name; messageIsError = false; password = ""; phase = "password"; return }
        const env = [
            "XDG_SESSION_TYPE=wayland",
            "XDG_SESSION_DESKTOP=" + s.id,
            "XDG_CURRENT_DESKTOP=" + (s.desktop || s.name).split(";")[0],
        ]
        Greetd.launch(s.exec.split(" "), env, true)
    }
    function power(what) {
        if (demo) { message = "demo · " + what; messageIsError = false; return }
        Quickshell.execDetached(["systemctl", what])
    }
    Connections {
        target: Greetd
        function onAuthMessage(msg, error, responseRequired, echoResponse) {
            if (!responseRequired) { root.message = msg.trim(); root.messageIsError = error; return }
            root.echo = echoResponse
            root.prompt = msg.replace(/:\s*$/, "").trim().toLowerCase() || "password"
            if (root.password) { Greetd.respond(root.password); root.password = "" }
            else root.phase = "password"   // a further factor: ask for it
        }
        function onAuthFailure(msg) { root.fail(msg || "Authentication failed") }
        function onReadyToLaunch() { root.launch() }
        function onError(err) { root.fail(err) }
    }

    // ── the screen ───────────────────────────────────────────────────────
    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        color: root.bg
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "lastshell-greeter"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // top-left: host chip, the same shape as the bar's clock chip
        Chip {
            edge: "top"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: 8
            Row {
                height: parent.height
                spacing: 9; leftPadding: 12; rightPadding: 12
                LucideIcon { anchors.verticalCenter: parent.verticalCenter; name: "terminal"; color: Theme.rose }
                ValueText { text: root.hostname }
            }
        }

        // top-right: the clock chip, hour-hand face and all
        Chip {
            edge: "top"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.rightMargin: 8
            SystemClock { id: clock; precision: SystemClock.Minutes }
            Row {
                height: parent.height
                spacing: 9; leftPadding: 12; rightPadding: 12
                ValueText { text: Qt.formatDateTime(clock.date, "ddd, dd MMM   hh:mm AP") }
                Canvas {
                    id: face
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    readonly property real hour12: (clock.date.getHours() % 12) + clock.date.getMinutes() / 60
                    onHour12Changed: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d"); ctx.reset()
                        const c = width / 2, r = c - 1.5
                        ctx.lineWidth = 1.5; ctx.strokeStyle = Qt.alpha(Theme.text, 0.35)
                        ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke()
                        ctx.beginPath(); ctx.moveTo(c, c - r); ctx.lineTo(c, c - r + 2.5); ctx.stroke()
                        const a = hour12 / 12 * 2 * Math.PI - Math.PI / 2
                        ctx.lineWidth = 2; ctx.lineCap = "round"; ctx.strokeStyle = Theme.rose
                        ctx.beginPath(); ctx.moveTo(c, c)
                        ctx.lineTo(c + Math.cos(a) * r * 0.62, c + Math.sin(a) * r * 0.62); ctx.stroke()
                        ctx.fillStyle = Theme.rose
                        ctx.beginPath(); ctx.arc(c, c, 1.5, 0, 2 * Math.PI); ctx.fill()
                    }
                }
            }
        }

        // bottom: hint chips, the two on the right are live buttons
        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            HintChip { icon: "corner-down-left"; label: "login" }
            HintChip { icon: "arrow-up-down"; label: "session" }
            HintChip { icon: "user"; label: "F1 user"; onClicked: { root.phase = "user"; root.message = ""; root.password = "" } }
            HintChip { icon: "rotate-ccw"; label: "F2 reboot"; accent: Theme.gold; onClicked: root.power("reboot") }
            HintChip { icon: "power"; label: "F3 power off"; accent: Theme.love; onClicked: root.power("poweroff") }
        }

        // ── the card ────────────────────────────────────────────────────
        Rectangle {
            id: card
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -24
            width: 560
            implicitHeight: body.implicitHeight + 4
            radius: Theme.overlayRadius
            color: Theme.surface
            border.color: Theme.border
            border.width: 2
            focus: true

            // entrance, the same as an overlay opening
            opacity: 0; scale: 0.97
            Component.onCompleted: { opacity = 1; scale = 1 }
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            // a bad password: the card flinches
            property real jolt: 0
            transform: Translate { x: card.jolt }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: card; property: "jolt"; to: -10; duration: 40 }
                NumberAnimation { target: card; property: "jolt"; to: 10; duration: 60 }
                NumberAnimation { target: card; property: "jolt"; to: -6; duration: 50 }
                NumberAnimation { target: card; property: "jolt"; to: 6; duration: 50 }
                NumberAnimation { target: card; property: "jolt"; to: 0; duration: 40 }
            }
            Connections { target: root; function onFailed() { shake.restart() } }

            Keys.onPressed: event => {
                const k = event.key, ctrl = event.modifiers & Qt.ControlModifier
                const n = root.sessions.length
                if (k === Qt.Key_F2) root.power("reboot")
                else if (k === Qt.Key_F3) root.power("poweroff")
                else if (k === Qt.Key_F1 || (ctrl && k === Qt.Key_L)) { root.phase = "user"; root.message = ""; root.password = "" }
                else if (k === Qt.Key_Escape) {
                    if (root.phase === "user") root.phase = "password"
                    else if (root.phase === "busy") { if (!root.demo) Greetd.cancelSession(); root.fail("cancelled") }
                    else { root.password = ""; root.message = "" }
                }
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.submit()
                else if (k === Qt.Key_Down || k === Qt.Key_Tab) {
                    if (root.phase === "user" && root.users.length) {
                        root.userIndex = (root.userIndex + 1) % root.users.length; root.user = root.users[root.userIndex]
                    } else if (n) root.sessionIndex = (root.sessionIndex + 1) % n
                }
                else if (k === Qt.Key_Up || k === Qt.Key_Backtab) {
                    if (root.phase === "user" && root.users.length) {
                        root.userIndex = (root.userIndex - 1 + root.users.length) % root.users.length; root.user = root.users[root.userIndex]
                    } else if (n) root.sessionIndex = (root.sessionIndex - 1 + n) % n
                }
                else if (k === Qt.Key_Backspace) {
                    if (root.phase === "user") root.user = root.user.slice(0, -1)
                    else if (root.phase === "password") root.password = root.password.slice(0, -1)
                }
                else if (ctrl && k === Qt.Key_U) { if (root.phase === "user") root.user = ""; else root.password = "" }
                else if (event.text && event.text >= " " && !ctrl) {
                    if (/[a-z]/i.test(event.text))
                        root.capsLock = (event.text === event.text.toUpperCase()) !== !!(event.modifiers & Qt.ShiftModifier)
                    if (root.phase === "user") root.user += event.text
                    else if (root.phase === "password") root.password += event.text
                    else return
                }
                else return
                event.accepted = true
            }

            Column {
                id: body
                anchors.fill: parent
                anchors.margins: 2

                // ── header: who
                Rectangle {
                    width: parent.width; height: 54
                    topLeftRadius: 6; topRightRadius: 6
                    color: Theme.overlay
                    MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: { root.phase = "user"; root.message = ""; root.password = "" } }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 18; spacing: 12
                        LucideIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "user"; font.pixelSize: 18
                            color: root.phase === "user" ? Theme.rose : Qt.alpha(Theme.text, 0.45)
                        }
                        LucideIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "chevron-right"; font.pixelSize: 14; color: Qt.alpha(Theme.text, 0.35)
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.fontFamily; font.pixelSize: 17
                                color: root.phase === "user" ? Theme.text : Qt.alpha(Theme.text, 0.8)
                                text: root.user || (root.phase === "user" ? "" : "who?")
                            }
                            Caret { on: root.phase === "user" }
                        }
                    }
                    Text { // hostname, right-aligned and quiet
                        anchors.right: parent.right; anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily; font.pixelSize: 13
                        color: Qt.alpha(Theme.text, 0.35)
                        text: "@" + root.hostname
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.alpha("#000000", 0.35) }

                // ── secret: the same field treatment as the row above
                Rectangle {
                    width: parent.width; height: 54
                    color: Theme.overlay
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.IBeamCursor
                        onClicked: if (root.phase === "user") root.submit()
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 18; spacing: 12
                        LucideIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 18
                            name: root.phase === "busy" ? "shield-check" : root.phase === "launch" ? "log-in" : "key-round"
                            color: root.phase === "busy" || root.phase === "launch" ? Theme.foam
                                 : root.messageIsError && root.message ? Theme.love
                                 : root.phase === "password" ? Theme.rose : Qt.alpha(Theme.text, 0.45)
                        }
                        LucideIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "chevron-right"; font.pixelSize: 14; color: Qt.alpha(Theme.text, 0.35)
                        }
                        Item { // typed value, caret at its end, ghost prompt after the caret
                            anchors.verticalCenter: parent.verticalCenter
                            height: 22
                            width: value.implicitWidth + (value.text ? 2 : 0) + 2
                                 + (ghost.visible ? ghost.implicitWidth + 8 : 0) + (pulse.visible ? 14 : 0)
                            Text {
                                id: value
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.fontFamily; font.pixelSize: 17
                                color: root.phase === "password" ? Theme.text : Qt.alpha(Theme.text, 0.6)
                                text: root.phase === "busy" ? "authenticating"
                                    : root.phase === "launch" ? "starting " + (root.sessions[root.sessionIndex]?.name ?? "")
                                    : root.echo ? root.password : "●".repeat(root.password.length)
                                Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                            }
                            Caret {
                                id: caret
                                x: value.implicitWidth + (value.text ? 2 : 0)
                                on: root.phase === "password"
                            }
                            Text { // the prompt as a ghost: it never captures the caret
                                id: ghost
                                x: caret.x + 8
                                anchors.verticalCenter: parent.verticalCenter
                                visible: (root.phase === "password" || root.phase === "user") && !root.password
                                font.family: Theme.fontFamily; font.pixelSize: 17
                                color: Qt.alpha(Theme.text, 0.3)
                                text: root.prompt
                            }
                            Pulse { id: pulse; x: value.implicitWidth + 8; on: root.phase === "busy" || root.phase === "launch" }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.alpha("#000000", 0.35) }

                // ── sessions: rows under a gliding rose outline
                Item {
                    width: parent.width
                    readonly property int rowH: 40
                    height: Math.max(1, root.sessions.length) * (rowH + 2) + 18
                    Rectangle { // the cursor
                        x: 8; width: parent.width - 16; height: parent.rowH
                        y: 9 + root.sessionIndex * (parent.rowH + 2)
                        radius: Theme.innerRadius; color: "transparent"
                        border.color: Theme.rose; border.width: 2
                        visible: root.sessions.length > 0
                        Behavior on y { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
                    }
                    Column {
                        x: 8; y: 9; width: parent.width - 16; spacing: 2
                        Repeater {
                            model: root.sessions
                            delegate: Item {
                                required property var modelData
                                required property int index
                                width: parent.width; height: 40
                                MouseArea { anchors.fill: parent; onClicked: root.sessionIndex = parent.index; onDoubleClicked: root.submit() }
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 14; spacing: 12
                                    LucideIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "app-window"; font.pixelSize: 15
                                        color: index === root.sessionIndex ? Theme.rose : Qt.alpha(Theme.text, 0.45)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: Theme.fontFamily; font.pixelSize: 15
                                        color: index === root.sessionIndex ? Theme.text : Qt.alpha(Theme.text, 0.7)
                                        text: modelData.name
                                    }
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: Theme.fontFamily; font.pixelSize: 12
                                    color: Qt.alpha(Theme.text, 0.3)
                                    text: modelData.exec.split(" ")[0].replace(/^.*\//, "")
                                }
                            }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.alpha("#000000", 0.35) }

                // ── footer: hints, and the message channel
                Rectangle {
                    width: parent.width; height: 34
                    bottomLeftRadius: 6; bottomRightRadius: 6
                    color: Theme.surface
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily; font.pixelSize: 13
                        color: root.capsLock ? Theme.gold : Qt.alpha(Theme.text, 0.35)
                        text: root.capsLock ? "⇪ caps lock is on"
                            : root.phase === "user" ? "⏎ done · ↑↓ users · esc back"
                            : root.demo ? "demo · password is  pass" : "⏎ login · ↑↓ session"
                        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.55
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                        font.family: Theme.fontFamily; font.pixelSize: 13
                        color: root.messageIsError ? Theme.love : Theme.foam
                        text: root.message
                        opacity: root.message ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animDuration } }
                    }
                }
            }
        }
    }

    // ── small parts ──────────────────────────────────────────────────────
    component Caret: Rectangle {
        property bool on: false
        anchors.verticalCenter: parent.verticalCenter
        width: 2; height: 22; color: Theme.rose
        visible: on
        SequentialAnimation on opacity {
            running: on; loops: Animation.Infinite
            NumberAnimation { to: 0; duration: 500 }
            NumberAnimation { to: 1; duration: 500 }
        }
    }
    component Pulse: Rectangle { // a breathing foam dot while greetd works
        property bool on: false
        anchors.verticalCenter: parent.verticalCenter
        width: 8; height: 8; radius: 4; color: Theme.foam
        visible: on
        SequentialAnimation on scale {
            running: on; loops: Animation.Infinite
            NumberAnimation { to: 0.5; duration: 450; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutSine }
        }
    }
    component HintChip: Chip {
        property string icon
        property string label
        edge: "bottom"
        Row {
            height: parent.height
            spacing: 8; leftPadding: 12; rightPadding: 12
            LucideIcon { anchors.verticalCenter: parent.verticalCenter; name: icon; font.pixelSize: 14; color: Qt.alpha(Theme.text, 0.55) }
            ValueText { text: label; font.pixelSize: 14; color: Qt.alpha(Theme.text, 0.55) }
        }
    }
}
