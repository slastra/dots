pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The shell's colors and measures. Colors are not chosen here: they come
// from the terminal's color scheme (kitty's colors.conf: background,
// foreground, color0-15), and every surface asks for a ROLE, never a hue.
// Swap the scheme file and the whole shell follows, live.
Singleton {
    id: root

    // ---- the scheme, as the terminal has it
    readonly property string schemePath: Quickshell.env("LASTSHELL_SCHEME")
        || (Quickshell.env("HOME") + "/.config/kitty/colors.conf")
    property var scheme: ({})
    function parse(text) {
        const out = {}
        for (const line of text.split("\n")) {
            const m = line.match(/^\s*([a-z_0-9]+)\s+(#[0-9a-fA-F]{6})\b/)
            if (m) out[m[1]] = m[2]
        }
        return out
    }
    FileView {
        path: root.schemePath
        blockLoading: true      // read before the bars build: no flash of the fallback
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.scheme = root.parse(text())
    }
    // ---- the shape: corner radius and border thickness, in pixels. Set for
    // the whole desktop with `tint shape --radius N --border N`, which writes
    // this file (and Hyprland's and GTK's numbers beside it).
    readonly property string shapePath: Quickshell.env("LASTSHELL_SHAPE")
        || (Quickshell.env("HOME") + "/.config/tint/out/shape.json")
    property var shape: ({})
    FileView {
        path: root.shapePath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.shape = JSON.parse(text()) } catch (e) { root.shape = {} } }
    }
    function px(v, fallback, max) {
        const n = Math.round(Number(v))
        return isFinite(n) ? Math.max(0, Math.min(max, n)) : fallback
    }

    // the fallbacks are Vague on black, for a host with no scheme file (the greeter)
    function slot(name, fallback) { return scheme[name] ?? fallback }
    // The see-through end of a fade. Never "transparent" for this: that is
    // transparent BLACK, so a fade to or from it passes through a dark,
    // half-opaque middle and the surface flashes before it lights.
    function clear(c) { return Qt.alpha(c, 0) }
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }

    // ---- neutrals: the background, stepped toward the foreground
    readonly property color base:    slot("background", "#000000")
    readonly property color text:    slot("foreground", "#cdcdcd")
    readonly property color surface: mix(base, text, 0.04)   // plates, cards
    readonly property color overlay: mix(base, text, 0.09)   // hover, bands, wells
    readonly property color border:  mix(base, text, 0.20)   // the hairline

    // ---- roles: one meaning each, the same on every surface. On a dark
    // background they take the scheme's bright variants (color9-14), which
    // are the ones drawn to be read against it; on a light one, the normal.
    readonly property bool dark: 0.299 * base.r + 0.587 * base.g + 0.114 * base.b < 0.5
    function hue(n, fallback) {
        const normal = slot("color" + n, fallback)
        return dark ? slot("color" + (n + 8), normal) : normal
    }
    // the accent and the secondary may be pinned to one of the scheme's hues
    // (`tint look`, the Look dialog); the shape file then carries the color
    function pinned(v) { return typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v) ? v : "" }
    readonly property color accent: pinned(shape.accent) || hue(6, "#bebeda")   // focus, the active item, selection
    // `quiet` is the one-accent look: color marks what is active or on
    // (accent) and what needs attention (warn, crit), and nothing else.
    // Readings in their normal range are plain text and the supporting
    // hues fold into the accent or a neutral. Set it false for a hue per role.
    readonly property bool quiet: true
    readonly property color neutral: mix(base, text, 0.6)
    readonly property color ok:     quiet ? accent : hue(2, "#99b782")    // on, live, healthy
    readonly property color warn:   hue(3, "#f5cb96")   // waiting on you, warning
    readonly property color crit:   hue(1, "#e08398")   // critical, destructive, recording
    readonly property color info:   quiet ? accent : hue(4, "#8ba9c1")    // network, links, slider fills
    readonly property color agent:  quiet ? neutral : hue(5, "#c9b1ca")   // Claude, the voice assistants, labels
    readonly property color calm:   quiet ? text : ok   // a reading in its normal range

    // ---- the secondary: the color of the small print (a popout's note, a
    // dialog's footer: key hints, counts, where the data is from). That text
    // is small and usually worth reading, and a faint gray made it hard to.
    // A terminal scheme names no such color, so it is
    // read out of one: the scheme's blue, or its magenta when the blue is
    // gray or too near the accent's hue, or failing both the accent pulled
    // halfway to the text. Whatever is chosen is then stepped toward the
    // text until it reads at 4.5:1 on a card.
    function luminance(c) {
        const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }
    function contrast(a, b) {
        const la = luminance(a), lb = luminance(b)
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }
    function readable(c) {
        let out = c
        for (let i = 0; i < 12 && contrast(out, surface) < 4.5; i++) out = mix(out, text, 0.15)
        return out
    }
    function ownHue(c) {   // colored, and not the accent over again
        if (c.hslSaturation < 0.12) return false
        if (accent.hslSaturation < 0.12) return true
        const d = Math.abs(c.hslHue - accent.hslHue)
        return Math.min(d, 1 - d) > 0.06
    }
    readonly property color secondary: {
        if (pinned(shape.secondary)) return readable(Qt.color(shape.secondary))
        const blue = Qt.color(hue(4, "#8ba9c1")), magenta = Qt.color(hue(5, "#c9b1ca"))
        return readable(ownHue(blue) ? blue : ownHue(magenta) ? magenta : mix(accent, text, 0.5))
    }

    // text at the alphas the popouts settled on; `track` is the neutral
    // slider/ring track, `divider` the rule between popout sections,
    // `seam` the hairline under modal headers and over footers
    readonly property color textMuted: Qt.alpha(text, 0.45)
    readonly property color textFaint: Qt.alpha(text, 0.35)
    readonly property color track:     Qt.alpha(text, 0.22)
    readonly property color divider:   overlay
    readonly property color seam:      border

    // ---- shape: lines and plates. Nothing is rounded but the instruments
    // (clock, rings, dots), which draw their own circles.
    // Both come from the shape file; square with a 1 px line without one.
    // `hairline` is every frame, divider and separator; `overlayRadius` the
    // corners of plates and floating cards, `innerRadius` of what sits inside.
    readonly property int hairline: px(shape.border, 1, 8)
    readonly property int overlayRadius: px(shape.radius, 0, 32)
    readonly property int innerRadius: Math.round(overlayRadius / 2)
    // a fill that sits flush inside a framed corner: concentric with the
    // frame's inner edge, so it neither pokes past the hairline nor gaps
    readonly property int insetRadius: Math.max(0, overlayRadius - hairline)
    // the header and footer bands of a modal, which sit 2 px inside its card
    readonly property int bandRadius: Math.max(0, overlayRadius - 2)

    readonly property int barHeight: 34
    // The font and its scale come from the shape file too (`tint look
    // --font`, a pair from tint's fonts.toml). Sizes around the shell were
    // chosen for the narrow ShureTechMono, the font without a shape file;
    // a wider face brings a scale under 1 with it.
    readonly property string fontFamily: shape.font || "ShureTechMono Nerd Font"
    readonly property real fontScale: Number(shape.fontScale) > 0 ? Number(shape.fontScale) : 1
    function fs(n) { return Math.round(n * fontScale) }
    // What ShellText places text by. The height of a capital or digit as a
    // share of the font size, measured at a large size: at text size the
    // answer is rounded to whole pixels and changes with the display scale
    // (10 at 1.0, 12 at 1.25 for the same 14 px Geist Mono).
    readonly property real capRatio: capProbe.tightBoundingRect("0").height / 400
    FontMetrics { id: capProbe; font.family: root.fontFamily; font.pixelSize: 400 }
    // The icons' ink rides this far above the middle of their box (measured
    // at 1.0 and 1.25 scale); text gives up the same to agree with them.
    readonly property real iconLift: 0.6
    // motion drops to 0 in eco mode: every animated frame is a bar repaint
    readonly property int animDuration: Eco.active ? 0 : 140
    readonly property int slideDuration: Eco.active ? 0 : 220   // item enter/exit
    readonly property int dragDuration: Eco.active ? 0 : 80     // slider fill following the pointer
    readonly property int sweepDuration: Eco.active ? 0 : 320   // gauge/bar sweeps to a new value
    readonly property int blinkDuration: 500   // caret and REC pulse half-period
    readonly property int tipDelay: 400        // ChipTip hover delay
    readonly property int popoutGrace: 250     // Popout hide grace
    readonly property int popoutGap: 0         // popouts and tips hang flush off their plate
    // popouts come in three widths and one padding (see Popout.qml)
    readonly property int popS: 240
    readonly property int popM: 320
    readonly property int popL: 400
    readonly property int popPad: 12

    // Left-pad a metric to a fixed digit count, so an item keeps its width
    // as the value crosses 9→10 (the font is monospace; a change of width
    // re-centers the zone and slides everything beside it).
    function pad(v, n) { return String(v).padStart(n, " ") }

    // Threshold color: value against warn/crit cutoffs, `calm` by default.
    function level(v, warnAt, critAt, base) {
        return v >= critAt ? crit : v >= warnAt ? warn : (base ?? calm)
    }
}
