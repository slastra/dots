pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// wttrbar on a 30-minute cadence, exactly waybar's custom/weather.
Singleton {
    id: root

    property string text: ""
    property string tooltip: ""
    // parsed from the tooltip: current conditions + per-day hi/lo
    property var now: ({})
    property var days: []

    // Lucide icon for the current condition — a live binding, so the chip
    // follows every 30-min refresh, and Clear flips sun/moon by hour.
    readonly property string icon: {
        const c = (now.condition ?? "").toLowerCase()
        const night = new Date().getHours() < 6 || new Date().getHours() >= 20
        if (c.includes("thunder") || c.includes("lightning")) return "cloud-lightning"
        if (c.includes("snow") || c.includes("sleet") || c.includes("blizzard")) return "cloud-snow"
        if (c.includes("drizzle")) return "cloud-drizzle"
        if ((c.includes("rain") || c.includes("shower")) && c.includes("partly"))
            return (new Date().getHours() < 6 || new Date().getHours() >= 20) ? "cloud-moon-rain" : "cloud-sun-rain"
        if (c.includes("rain") || c.includes("shower")) return "cloud-rain"
        if (c.includes("haze")) return "haze"
        if (c.includes("fog") || c.includes("mist")) return "cloud-fog"
        if (c.includes("tornado")) return "tornado"
        if (c.includes("overcast") || c.includes("cloudy") && !c.includes("partly")) return "cloud"
        if (c.includes("partly")) return night ? "cloud-moon" : "cloud-sun"
        if (c.includes("sunny")) return "sun"
        if (c.includes("clear")) return night ? "moon" : "sun"
        return "cloud-sun"
    }

    Timer {
        interval: 1800000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    // wttrbar's tooltip is a fixed shape: a current-conditions block, then
    // one <b>DayName, date</b> header per day followed by a hi/lo line.
    // Distil it: the hourly rows are noise at popout scale.
    function parse(tip) {
        const lines = tip.split("\n")
        const n = {}
        const cond = lines[0]?.match(/<b>(.+)<\/b>\s*(-?\d+)°/)
        if (cond) { n.condition = cond[1]; n.temp = cond[2] }
        for (const l of lines.slice(1, 6)) {
            let m
            if ((m = l.match(/Feels Like:\s*(-?\d+)°/))) n.feels = m[1]
            else if ((m = l.match(/Wind:\s*(.+)/))) n.wind = m[1]
            else if ((m = l.match(/Humidity:\s*(.+)/))) n.humidity = m[1]
        }
        const d = []
        for (let i = 0; i < lines.length - 1; i++) {
            const h = lines[i].match(/^<b>([^,<]+)(?:, [\d-]+)?<\/b>$/)
            if (!h) continue
            const hl = lines[i + 1].match(/(-?\d+)°.*?(-?\d+)°/)
            if (!hl) continue
            // beyond Today/Tomorrow the header is a bare date — show the
            // weekday name instead ("Wednesday" beats "2026-09-02")
            let name = h[1]
            if (/^\d{4}-\d{2}-\d{2}$/.test(name))
                name = Qt.formatDate(new Date(name + "T12:00:00"), "dddd")
            d.push({ name: name, hi: hl[1], lo: hl[2] })
        }
        root.now = n
        root.days = d
    }

    Process {
        id: proc
        command: ["wttrbar", "--fahrenheit", "--mph", "--nerd",
                  "--custom-indicator", "{temp_F}°F {ICON}"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text)
                    root.text = j.text ?? ""
                    root.tooltip = j.tooltip ?? ""
                    root.parse(j.tooltip ?? "")
                } catch (e) { /* network hiccup; old value stands */ }
            }
        }
    }
}
