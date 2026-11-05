#!/usr/bin/env python3
"""
Recording border overlay using gtk4-layer-shell
Draws a colored border and dim mask around the recording region
Usage: recording-border.py WxH+X+Y
"""

import sys
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Gtk4LayerShell', '1.0')
from gi.repository import Gtk, Gtk4LayerShell, Gdk
import cairo

# Rosé Pine love color for border
BORDER_COLOR = (0.922, 0.435, 0.573, 1.0)  # #eb6f92
# Rosé Pine base color for mask (semi-transparent)
MASK_COLOR = (0.098, 0.09, 0.141, 0.7)  # #191724 at 70% opacity
BORDER_WIDTH = 3
# Clear space between the recorded region and the border. Everything this
# overlay draws must stay OUTSIDE the region, or gpu-screen-recorder records
# it. At a fractional scale (1.25 on the desk) a logical edge falls mid-pixel,
# so the recorder's edge pixel can blend in whatever is drawn next to it: the
# gap keeps that neighbour live screen content instead of the pink stroke.
GAP = 2


def parse_geometry(geom_str):
    """Parse WxH+X+Y format"""
    # Split on + to get WxH and X, Y
    parts = geom_str.replace('-', '+-').split('+')
    wh = parts[0]
    x = int(parts[1]) if len(parts) > 1 else 0
    y = int(parts[2]) if len(parts) > 2 else 0

    w, h = wh.split('x')
    return int(x), int(y), int(w), int(h)


class MaskOverlay(Gtk.ApplicationWindow):
    def __init__(self, app, region_x, region_y, region_w, region_h):
        super().__init__(application=app)

        self.region_x = region_x
        self.region_y = region_y
        self.region_w = region_w
        self.region_h = region_h

        # Get screen dimensions
        display = Gdk.Display.get_default()
        monitors = display.get_monitors()
        # Use primary monitor dimensions
        monitor = monitors.get_item(0)
        geom = monitor.get_geometry()
        self.screen_w = geom.width
        self.screen_h = geom.height

        # Set up layer shell - fullscreen overlay
        Gtk4LayerShell.init_for_window(self)
        Gtk4LayerShell.set_layer(self, Gtk4LayerShell.Layer.OVERLAY)
        # Anchor to all edges for fullscreen
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.TOP, True)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.BOTTOM, True)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.LEFT, True)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.RIGHT, True)
        Gtk4LayerShell.set_exclusive_zone(self, -1)  # Don't reserve space
        Gtk4LayerShell.set_keyboard_mode(self, Gtk4LayerShell.KeyboardMode.NONE)

        # Create drawing area
        drawing_area = Gtk.DrawingArea()
        drawing_area.set_hexpand(True)
        drawing_area.set_vexpand(True)
        drawing_area.set_draw_func(self.on_draw)
        drawing_area.set_can_target(False)
        self.set_child(drawing_area)

        # Make window transparent and non-interactive
        self.add_css_class('transparent')
        self.set_can_target(False)

        # Set empty input region to allow click-through
        self.connect('realize', self.on_realize)

    def on_realize(self, widget):
        """Set empty input region after window is realized"""
        surface = self.get_surface()
        if surface:
            # Create empty region for complete click-through
            empty_region = cairo.Region(cairo.RectangleInt(0, 0, 0, 0))
            surface.set_input_region(empty_region)

    def on_draw(self, area, cr, width, height):
        # Clear background (transparent)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        x, y, w, h = self.region_x, self.region_y, self.region_w, self.region_h

        # Mask everything beyond the border's outer edge (even-odd: the
        # full screen minus the framed hole)
        outer = GAP + BORDER_WIDTH
        cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
        cr.set_source_rgba(*MASK_COLOR)
        cr.rectangle(0, 0, width, height)
        cr.rectangle(x - outer, y - outer, w + 2 * outer, h + 2 * outer)
        cr.fill()

        # Border band from GAP to GAP + BORDER_WIDTH outside the region
        cr.set_source_rgba(*BORDER_COLOR)
        cr.rectangle(x - outer, y - outer, w + 2 * outer, h + 2 * outer)
        cr.rectangle(x - GAP, y - GAP, w + 2 * GAP, h + 2 * GAP)
        cr.fill()


class BorderApp(Gtk.Application):
    def __init__(self, x, y, w, h):
        super().__init__(application_id='com.recording.border')
        self.x = x
        self.y = y
        self.w = w
        self.h = h

    def do_activate(self):
        # Add CSS for transparency
        css_provider = Gtk.CssProvider()
        css_provider.load_from_string('''
            window.transparent,
            window.transparent > *,
            window.transparent drawingarea {
                background-color: rgba(0, 0, 0, 0);
                background: transparent;
            }
        ''')
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_USER
        )

        win = MaskOverlay(self, self.x, self.y, self.w, self.h)
        win.present()


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} WxH+X+Y")
        sys.exit(1)

    try:
        x, y, w, h = parse_geometry(sys.argv[1])
    except (ValueError, IndexError) as e:
        print(f"Invalid geometry: {sys.argv[1]}")
        print(f"Expected format: WxH+X+Y (e.g., 800x600+100+200)")
        sys.exit(1)

    app = BorderApp(x, y, w, h)
    app.run([])


if __name__ == '__main__':
    main()
