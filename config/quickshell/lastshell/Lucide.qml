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
        "square":        "\ue167",
        "music":         "\ue122",
        "sparkles":      "",
        "plus":          "\ue13d",
        // greeter
        "user":              "\ue19f",
        "key-round":         "\ue4a3",
        "power":             "\ue140",
        "rotate-ccw":        "\ue148",
        "corner-down-left":  "\ue0a1",
        "log-in":            "\ue10d",
        "arrow-up-down":     "\ue37d",
        "shield-check":      "\ue1ff",
        "terminal":          "\ue181",
        "sun": "\ue178",
        "wifi":          "\ue1ae",
        "wifi-off":      "\ue1af",
        "lightbulb": "\ue1c2",
        "lightbulb-off": "\ue208",
        "moon": "\ue11e",
        "cloud": "\ue088",
        "cloud-sun": "\ue216",
        "cloud-moon": "\ue215",
        "cloud-rain": "\ue08e",
        "cloud-drizzle": "\ue08a",
        "cloud-snow": "\ue090",
        "cloud-lightning": "\ue08c",
        "cloud-fog": "\ue214",
        "haze": "\ue0f0",
        "cloud-sun-rain": "\ue2fb",
        "cloud-moon-rain": "\ue2fa",
        "tornado": "\ue218",
        "search": "\ue151",
        "rocket": "\ue286",
        "app-window": "\ue426",
        "chevron-right": "\ue06f",
        "wand-sparkles": "\ue357",
        "check": "\ue06c",
        "volume-2": "\ue1ab",
        "volume-x": "\ue1ac",
        "coffee": "\ue096",
        "timer": "\ue1e0",
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
        // deskwatch
        "activity": "\ue038",
        "shield-alert": "\ue1fe",
        "radar": "\ue497",
        // deskwatch level glyphs, worst to mildest
        "siren":          "\ue2ef",
        "alert-octagon":  "\ue127",
        "eye":            "\ue0ba",
        "info":           "\ue0f9",
    })

    function icon(name) { return glyphs[name] ?? "?" }
}
