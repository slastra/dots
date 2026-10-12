import Quickshell
import QtQuick
import ".."  // root module: Wifi

// Wi-Fi network picker (laptop; Super+Shift+N or a click on the network chip).
// Opens on the last known list and scans once. The joined network sits on
// top, then saved ones, then the rest, each by signal. Enter joins: a saved
// or open network straight away, a new secured one through WifiPassword.
SearchOverlay {
    id: root

    typeIcon: "wifi"
    visibleRows: 10
    hint: Wifi.scanning ? "scanning…   ↵ connect   esc close" : "↑↓ navigate   ↵ connect   esc close"

    onOpenChanged: {
        Wifi.pickerOpen = open
        if (open) Wifi.scan()
    }

    function bars(dbm) {
        return dbm >= -60 ? "wifi" : dbm >= -70 ? "wifi-high" : dbm >= -80 ? "wifi-low" : "wifi-zero"
    }

    items: Wifi.networks.map(n => ({
        key: n.name,
        label: n.name,
        current: n.connected,
        lucideIcon: bars(n.signal),
        trailIcon: n.known || n.type === "open" ? "" : "lock",
        weight: n.connected ? 10000 : n.known ? 1000 + n.signal : 100 + n.signal,
        net: n,
    }))

    onActivated: item => {
        const n = item.net
        if (n.connected) return
        if (n.known || n.type === "open") Wifi.connect(n.name)
        else if (n.type === "8021x")
            Quickshell.execDetached(["notify-send", "-a", "Wi-Fi", "-i", "network-wireless",
                `Can't join ${n.name}`, "Enterprise (802.1X) networks need an iwd profile"])
        else Wifi.askFor = n.name
    }
}
