#!/bin/sh
# Emit one line per Wayland session: name<TAB>exec<TAB>desktopnames<TAB>id
# Hyprland first, the rest alphabetical. Skips ids matching
# $LASTSHELL_GREETER_HIDE (grep -E pattern; default hides the uwsm twin).
hide=${LASTSHELL_GREETER_HIDE:-'-uwsm$'}
emit() {
    f=$1; id=$(basename "$f" .desktop)
    printf "%s" "$id" | grep -Eq -- "$hide" && return
    printf '%s\t%s\t%s\t%s\n' \
        "$(sed -n 's/^Name=//p' "$f" | head -1)" \
        "$(sed -n 's/^Exec=//p' "$f" | head -1)" \
        "$(sed -n 's/^DesktopNames=//p' "$f" | head -1)" "$id"
}
[ -r /usr/share/wayland-sessions/hyprland.desktop ] && emit /usr/share/wayland-sessions/hyprland.desktop
for f in /usr/share/wayland-sessions/*.desktop; do
    [ -r "$f" ] || continue
    [ "$(basename "$f")" = hyprland.desktop ] && continue
    emit "$f"
done
