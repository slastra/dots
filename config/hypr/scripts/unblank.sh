#!/bin/sh
# Input is back: lift lastshell's blackout (black screen shader + hidden
# cursor) if it is still applied. lastshell's DimOverlay clears it itself when
# deskpresence lifts the fade; this is the net for a shell or daemon that died
# mid-blackout. Called from hypridle's quiet listener on-resume.
case "$(hyprctl getoption decoration:screen_shader)" in
*blackout.frag*)
	hyprctl eval 'hl.config({ decoration = { screen_shader = "" }, cursor = { invisible = false } })' >/dev/null
	;;
esac
