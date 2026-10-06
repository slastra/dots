pragma Singleton
import QtQuick

// Rosé Pine.
QtObject {
    readonly property color base:    "#191724"
    readonly property color surface: "#201D2F"
    readonly property color overlay: "#26233A"
    readonly property color border:  "#403D52"   // highlight med; = hyprland theme.lua border_inactive
    readonly property color text:    "#E0DEF4"
    readonly property color love:    "#EB6F92"
    readonly property color gold:    "#F6C177"
    readonly property color rose:    "#EBBCBA"
    readonly property color pine:    "#31748F"
    readonly property color foam:    "#9CCFD8"
    readonly property color iris:    "#C4A7E7"

    // text at the alphas the popouts settled on; `track` is the neutral
    // slider/ring track, `divider` the rule between popout sections,
    // `seam` the hard line under modal headers and over footers
    readonly property color textMuted: Qt.alpha(text, 0.45)
    readonly property color textFaint: Qt.alpha(text, 0.35)
    readonly property color track:     Qt.alpha(text, 0.22)
    readonly property color divider:   overlay
    readonly property color seam:      Qt.alpha("#000000", 0.35)

    readonly property int barHeight: 34
    readonly property string fontFamily: "ShureTechMono Nerd Font"
    readonly property int animDuration: 140
    readonly property int slideDuration: 220   // chip enter/exit slide
    readonly property int dragDuration: 80     // slider fill following the pointer
    readonly property int sweepDuration: 320   // gauge/bar sweeps to a new value
    readonly property int blinkDuration: 500   // caret and REC pulse half-period
    readonly property int tipDelay: 400        // ChipTip hover delay
    readonly property int popoutGrace: 250     // Popout hide grace across the gap
    readonly property int overlayRadius: 12   // = hyprland rounding = libadwaita window radius
    readonly property int innerRadius: 6      // rows/pills nested inside an overlayRadius frame

    // Threshold color: value against warn/crit cutoffs, foam family base.
    function level(v, warn, crit, base) {
        return v >= crit ? love : v >= warn ? gold : (base ?? foam)
    }
}
