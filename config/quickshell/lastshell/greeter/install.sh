#!/usr/bin/env bash
# Install the lastshell greeter for greetd.   sudo bash greeter/install.sh
# Rollback to ReGreet:  sudo cp /etc/greetd/config.toml.regreet /etc/greetd/config.toml
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
DEST=/usr/local/share/lastshell-greeter
STATE=/var/lib/lastshell-greeter

install -d "$DEST/greeter/assets"
# the shared root module pieces the greeter imports via ".."
install -m 0644 "$REPO"/{Theme,Chip,LucideIcon,Lucide,ValueText}.qml "$DEST/"
printf '%s\n' 'singleton Theme 1.0 Theme.qml' 'Chip 1.0 Chip.qml' 'LucideIcon 1.0 LucideIcon.qml' \
               'singleton Lucide 1.0 Lucide.qml' 'ValueText 1.0 ValueText.qml' > "$DEST/qmldir"
install -m 0644 "$REPO"/greeter.qml "$DEST/"
install -m 0644 "$REPO"/greeter/{Greeter.qml,hyprland-greeter.lua} "$DEST/greeter/"
install -m 0755 "$REPO"/greeter/sessions.sh "$DEST/greeter/"
install -m 0644 "$REPO"/greeter/assets/lucide.ttf "$DEST/greeter/assets/"

# greeter's HOME is "/" — give Quickshell and Hyprland somewhere writable
install -d -o greeter -g greeter -m 0750 "$STATE"

[ -e /etc/greetd/config.toml.regreet ] || cp -a /etc/greetd/config.toml /etc/greetd/config.toml.regreet
cat > /etc/greetd/config.toml <<CONF
[terminal]
vt = 1

[default_session]
command = "env HOME=$STATE XDG_CACHE_HOME=$STATE/cache XDG_CONFIG_HOME=$STATE/config XDG_DATA_HOME=$STATE/data start-hyprland -- --config $DEST/greeter/hyprland-greeter.lua"
user = "greeter"
CONF
echo "installed to $DEST; greetd will use it at the next login screen."
echo "rollback: sudo cp /etc/greetd/config.toml.regreet /etc/greetd/config.toml"
