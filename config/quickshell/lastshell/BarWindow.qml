import Quickshell
import QtQuick

// A bar shell: full-width transparent panel reserving its strip of the
// screen. (`reserve: false` existed for the parallel run with waybar.)
PanelWindow {
    property bool reserve: true
    implicitHeight: Theme.barHeight
    color: "transparent"
    exclusiveZone: reserve ? Theme.barHeight : 0
    anchors { left: true; right: true }
}
