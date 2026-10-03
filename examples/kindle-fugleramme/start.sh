#!/bin/sh
DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
STATE="$DIR/state"
PID_FILE="$STATE/client.pid"
mkdir -p "$STATE"

if [ -r "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        exit 0
    fi
    rm -f "$PID_FILE"
fi

(
    trap '' HUP
    # shellcheck disable=SC1090
    [ -r "$DIR/config.sh" ] && . "$DIR/config.sh"
    sleep "${START_DELAY_SECONDS:-5}"
    exec /bin/sh "$DIR/fugleramme.sh" >> "$STATE/fugleramme.log" 2>&1
) &
printf '%s\n' "$!" > "$PID_FILE"
sleep 1
kill -0 "$!" 2>/dev/null || rm -f "$PID_FILE"
