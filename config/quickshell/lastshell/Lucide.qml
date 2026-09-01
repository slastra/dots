pragma Singleton
import QtQuick

// Lucide icon font (user-level install: ~/.local/share/fonts/lucide.ttf).
// Codepoints extracted from lucide.css; add entries as needed. Stroke-style
// icons that sit naturally beside the drawn instruments.
QtObject {
    readonly property string family: "lucide"

    readonly property var glyphs: ({
        "hourglass":     "",
        "calendar-days": "",
        "cpu":           "",
        "memory-stick":  "",
        "hard-drive":    "",
        "ethernet-port": "",
        "unplug":        "",
        "circle-dot":    "",
        "play":          "",
        "pause":         "",
        "music":         "",
        "globe":         "",
        "sparkles":      "",
        "sun": "\ue178",
        "moon": "\ue11e",
        "cloud": "\ue088",
        "cloud-sun": "\ue216",
        "cloud-moon": "\ue215",
        "cloud-rain": "\ue08e",
        "cloud-drizzle": "\ue08a",
        "cloud-snow": "\ue090",
        "cloud-lightning": "\ue08c",
        "cloud-fog": "\ue214",
        "snowflake": "\ue165",
        "wind": "\ue1b0",
        "haze": "\ue0f0",
        "cloud-sun-rain": "\ue2fb",
        "cloud-moon-rain": "\ue2fa",
        "tornado": "\ue218",
        "search": "\ue151",
        "rocket": "\ue286",
        "app-window": "\ue426",
        "chevron-right": "\ue06f",
        "palette": "\ue1dd",
        "wand-sparkles": "\ue357",
        "check": "\ue06c",
        "volume-2": "\ue1ab",
        "clipboard-list": "\ue086",
        "image": "\ue0f6",
        "bell": "\ue059",
        "trash-2": "\ue18e",
        "inbox": "\ue0f7",
        "camera": "\ue064",
        "video": "\ue1a5",
        "monitor": "\ue11d",
        "square-dashed": "\ue1cb",
        "scan-barcode": "\ue535",
        "keyboard": "\ue284",
    })

    function icon(name) { return glyphs[name] ?? "?" }
}
