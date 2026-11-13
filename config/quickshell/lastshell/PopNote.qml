import QtQuick

// The small print of a popout: a graph's caption, where the data came from,
// what a click does. One size everywhere, in the secondary color so it
// stays readable at that size.
PopText {
    size: 11
    color: Theme.secondary
    width: parent ? parent.width : implicitWidth
    wrapMode: Text.WordWrap
}
