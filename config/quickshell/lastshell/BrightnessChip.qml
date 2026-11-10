import QtQuick

// Panel backlight chip, the laptop's counterpart to HdrChip. Wheel steps
// 5% of perceived brightness (Backlight.level), popout drags the full range, click toggles auto brightness (foam
// while it follows the light sensor). Absent wherever there is no backlight.
StatChip {
    id: root
    edge: "top"
    present: Backlight.present

    readonly property real b: Backlight.level
    value: `${Theme.pad(Math.round(b * 100), 3)}%`
    icon: "sun"
    tone: Backlight.autoActive ? Theme.ok : Theme.text

    onClicked: Backlight.toggleAuto()

    onWheelUp: Backlight.nudge(Backlight.step)
    onWheelDown: Backlight.nudge(-Backlight.step)

    Popout {
        owner: root
        title: "brightness"
        status: `${Math.round(root.b * 100)}%`
        note: Backlight.hasSensor
            ? "click: " + (Backlight.auto ? "manual" : "auto") + "  ·  adjusting sets the offset" : ""

        SliderTrack {
            width: parent.width
            frac: root.b
            interactive: true
            onSeek: f => Backlight.setLevel(f)
        }
        KeyValueRow { visible: Backlight.hasSensor; key: "mode"; value: Backlight.auto ? "auto" : "manual" }
        KeyValueRow {
            visible: Backlight.hasSensor && Backlight.auto
            key: "ambient"
            value: `${Math.round(Math.max(0, Backlight.lux))} lux`
        }
        KeyValueRow {
            visible: Backlight.hasSensor && Backlight.auto
            key: "offset"
            value: `${Backlight.offset >= 0 ? "+" : ""}${Math.round(Backlight.offset * 100)}%`
        }
    }
}
