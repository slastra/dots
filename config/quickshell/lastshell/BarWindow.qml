import Quickshell
import QtQuick

// A bar shell: full-width transparent panel reserving its strip of the
// screen.
PanelWindow {
    implicitHeight: Theme.barHeight
    color: "transparent"
    exclusiveZone: Theme.barHeight
    anchors { left: true; right: true }
}
