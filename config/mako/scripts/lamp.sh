#!/bin/bash
# Mako notification lamp control via MQTT
# Usage: lamp.sh <info|alert|idle> [notification_id]
#
# info  - publish info, start timer that publishes idle after TIMEOUT
# alert - publish alert, no timer (critical stays until manual reset)
# idle  - publish idle, kill timer, dismiss notif if id given

TYPE="${1:-idle}"
NOTIF_ID="$2"

MQTT_HOST="desk.local"
MQTT_TOPIC="odradek/control"
PIDFILE="/tmp/mako-lamp-timer.pid"
TIMEOUT=10

publish() {
    mosquitto_pub -h "$MQTT_HOST" -t "$MQTT_TOPIC" -m "{\"type\":\"$1\"}" &
}

kill_timer() {
    if [[ -f "$PIDFILE" ]]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
    fi
}

start_timer() {
    (
        sleep "$TIMEOUT"
        mosquitto_pub -h "$MQTT_HOST" -t "$MQTT_TOPIC" -m '{"type":"idle"}'
        rm -f "$PIDFILE"
    ) &
    echo $! > "$PIDFILE"
    disown
}

case "$TYPE" in
    info)
        kill_timer
        publish info
        start_timer
        ;;
    alert)
        kill_timer
        publish alert
        ;;
    idle)
        kill_timer
        publish idle
        [[ -n "$NOTIF_ID" ]] && makoctl dismiss -n "$NOTIF_ID"
        ;;
    *)
        echo "Usage: $0 <info|alert|idle> [notification_id]" >&2
        exit 1
        ;;
esac
