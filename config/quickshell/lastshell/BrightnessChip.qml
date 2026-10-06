import QtQuick

// Panel backlight chip, the laptop's counterpart to HdrChip. Wheel steps
// 5%, popout drags the full range, click toggles auto brightness (foam
// while it follows the light sensor). Absent wherever there is no backlight.
StatChip {
    id: root
    edge: "top"
    present: Backlight.present

    readonly property real b: Backlight.frac
    value: `${Math.round(b * 100)}%`
    icon: "sun"
    tone: Backlight.autoActive ? Theme.foam : Theme.text

    onClicked: Backlight.toggleAuto()

    onWheelUp: Backlight.nudge(Backlight.step)
    onWheelDown: Backlight.nudge(-Backlight.step)

    Popout {
        owner: root

        Column {
            spacing: 8
            PopText {
                text: `Brightness ${Math.round(root.b * 100)}%`
                size: 14
                width: 220
            }
            PopText {
                visible: Backlight.hasSensor
                text: Backlight.auto
                    ? `auto · ${Math.round(Math.max(0, Backlight.lux))} lux · ${Backlight.offset >= 0 ? "+" : ""}${Math.round(Backlight.offset * 100)}% offset`
                    : "manual"
                dim: 0.45
                size: 12
            }
            SliderTrack {
                width: 220
                frac: root.b
                fill: Theme.gold
                interactive: true
                onSeek: f => Backlight.set(f)
            }
            PopText {
                visible: Backlight.hasSensor
                text: "click: " + (Backlight.auto ? "manual" : "auto") + "  ·  adjusting sets the offset"
                dim: 0.45
                size: 12
            }
        }
    }
}
