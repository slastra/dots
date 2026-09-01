pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// One poller for cpu / memory / temperature (5s) and disk (30s).
// Chips are thin views over these properties — never poll per-chip.
Singleton {
    id: root

    property real cpuPct: 0
    property real memPct: 0
    property real tempC: 0
    property real diskPct: 0
    // tooltip detail
    property string loadAvg: ""
    property real memUsedGiB: 0
    property real memTotalGiB: 0
    property string diskUsed: ""
    property string diskTotal: ""

    property var _prev: null

    // blockLoading: procfs never signals changes, and reload() is async by
    // default — text() then hands back the previous (or empty) content, which
    // is how the first cut showed NaN% memory and a frozen 0% cpu.
    FileView { id: stat;    path: "/proc/stat";    blockLoading: true }
    FileView { id: meminfo; path: "/proc/meminfo"; blockLoading: true }
    FileView { id: loadavg; path: "/proc/loadavg"; blockLoading: true }

    Timer {
        interval: 5000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload(); meminfo.reload(); loadavg.reload()
            root._tick()
            temp.running = true
        }
    }
    Timer {
        interval: 30000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: df.running = true
    }

    function _tick() {
        try {
            const cols = stat.text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
            const idle = cols[3] + cols[4]
            const total = cols.reduce((a, b) => a + b, 0)
            if (_prev) {
                const dt = total - _prev.total, di = idle - _prev.idle
                if (dt > 0) cpuPct = Math.round(100 * (dt - di) / dt)
            }
            _prev = { total: total, idle: idle }

            const m = {}
            for (const line of meminfo.text().split("\n")) {
                const p = line.split(/\s+/)
                m[p[0]] = Number(p[1])
            }
            // waybar's memory {}%: used = total - available
            memPct = Math.round(100 * (m["MemTotal:"] - m["MemAvailable:"]) / m["MemTotal:"])
            memUsedGiB = (m["MemTotal:"] - m["MemAvailable:"]) / 1048576
            memTotalGiB = m["MemTotal:"] / 1048576
            loadAvg = loadavg.text().split(" ").slice(0, 3).join("  ")
        } catch (e) { /* mid-read; next tick corrects */ }
    }

    // Package temp: the same k10temp/coretemp source waybar's hwmon autodetect
    // lands on; grab the max across hwmon temp1 inputs to stay socket-agnostic.
    Process {
        id: temp
        command: ["sh", "-c", "cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | sort -n | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = Number(text.trim())
                if (v > 0) root.tempC = Math.round(v / 1000)
            }
        }
    }

    Process {
        id: df
        command: ["sh", "-c", "df -h --output=pcent,used,size / | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                const v = Number((p[0] ?? "").replace("%", ""))
                if (v > 0) {
                    root.diskPct = v
                    root.diskUsed = p[1] ?? ""
                    root.diskTotal = p[2] ?? ""
                }
            }
        }
    }
}
