import QtQuick
import ".."  // root module: Wifi, Theme

// Passphrase for a Wi-Fi network: a new secured one picked in WifiPicker, or
// iwd asking through the agent. Typed text is only ever drawn as dots and
// goes to wifi.py over stdin, never a command line. Stays open while joining
// and says why a join failed, so a mistyped password is retyped in place.
Overlay {
    id: root

    cardWidth: 460
    contentPadding: 2

    property string pass: ""
    property string status: ""
    readonly property bool joining: Wifi.connecting === Wifi.askFor && Wifi.askFor !== ""

    onOpenChanged: {
        Wifi.dialogOpen = open
        if (open) { pass = ""; status = "" }
        else {
            Wifi.cancel()
            Wifi.askFor = ""
        }
    }

    function submit() {
        // WPA needs 8 or more; iwd would only fail later and less clearly
        if (pass.length < 8) { status = "at least 8 characters"; return }
        status = ""
        Wifi.submit(Wifi.askFor, pass)
    }

    Connections {
        target: Wifi
        function onResult(name, ok, error) {
            if (!root.open || name !== Wifi.askFor) return
            if (ok) root.dismiss()
            else { root.status = error; root.pass = "" }
        }
    }

    Column {
        width: parent.width
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) root.dismiss()
            else if (root.joining) return
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.submit()
            else if (event.key === Qt.Key_Backspace) root.pass = root.pass.slice(0, -1)
            else if (event.text && event.text >= " ") { root.pass += event.text; root.status = "" }
            else return
            event.accepted = true
        }

        ModalHeader {
            icon: "lock"
            title: Wifi.askFor
            query: "•".repeat(root.pass.length)
            active: root.open && !root.joining
        }

        Item {
            width: parent.width
            height: 44
            PopText {
                anchors.verticalCenter: parent.verticalCenter
                x: 18
                size: 14
                color: root.status !== "" ? Theme.love : Theme.text
                dim: root.status !== "" ? 1 : 0.55
                text: root.joining ? "joining…"
                    : root.status !== "" ? root.status
                    : "password"
            }
        }

        ModalFooter {
            hint: root.joining ? "esc close" : "↵ join   esc cancel"
        }
    }
}
