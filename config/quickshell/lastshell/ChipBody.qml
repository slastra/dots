import QtQuick

// The content row every chip opens with: bar height (every Chip is
// Theme.barHeight - 2, its content slot two less), 8 px between parts.
// Chip.contentPadding supplies the side room.
Row {
    height: Theme.barHeight - 4
    spacing: 8
}
