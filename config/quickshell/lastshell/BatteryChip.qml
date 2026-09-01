import Quickshell.Services.UPower
import QtQuick

// Battery chip (waybar battery). Hidden entirely when no battery exists —
// this is a desktop; the chip appears only if UPower reports a display
// device that is present (e.g. a UPS or BT peripheral promoted to display).
Chip {
    id: root
    edge: "top"
    visible: UPower.displayDevice?.isPresent ?? false

    readonly property real pct: (UPower.displayDevice?.percentage ?? 0) * 100
    readonly property bool charging: UPower.displayDevice?.state === UPowerDeviceState.Charging

    ChipText {
        height: root.height
        padRight: 17
        color: Theme.level(100 - root.pct, 80, 90) // warn 20, crit 10 remaining
        text: {
            const ramp = root.charging
                ? ["󰢜","󰂆","󰂇","󰂈","󰢝","󰂉","󰢞","󰂊","󰂋","󰂅"]
                : ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"]
            if (root.pct >= 100 && !root.charging) return "Charged "
            const i = Math.min(9, Math.floor(root.pct / 10))
            return `${Math.round(root.pct)}% ${ramp[i]}`
        }
    }
}
