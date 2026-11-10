import QtQuick

// The small print of a popout: a graph's caption, where the data came from,
// what a click does. One size and one tone everywhere.
PopText {
    size: 11
    color: Theme.textFaint
    width: parent ? parent.width : implicitWidth
    wrapMode: Text.WordWrap
}
