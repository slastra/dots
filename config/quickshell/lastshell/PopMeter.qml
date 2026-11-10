import QtQuick

// A read-only fill bar in a popout (disk used, quota spent). Sliders the
// pointer can drag are SliderTrack at its full height; this is the thin one.
SliderTrack {
    width: parent ? parent.width : 0
    height: 4
    sweep: Theme.sweepDuration
}
