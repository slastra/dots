import QtQuick

// A Row of chips: neighbours glide rather than jump when a chip appears or
// leaves (the chip itself handles its own slide, see Chip).
Row {
    move: Transition { NumberAnimation { properties: "x"; duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
    add:  Transition { NumberAnimation { properties: "x"; duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
}
