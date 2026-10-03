#!/bin/sh
# Wait for Kindle powerd's physical-button/screensaver event, then ask the main
# client to exit through its normal restoration path.
set -u

CLIENT_PID=${1:-}
RUNTIME=${2:-/tmp/fugleramme}
FIFO="$RUNTIME/power-event.$$"
WAIT_PID=""

cleanup() {
    trap - EXIT
    [ -n "$WAIT_PID" ] && kill "$WAIT_PID" 2>/dev/null || true
    rm -f "$FIFO"
}

trap cleanup EXIT
trap 'exit 0' HUP INT TERM

case "$CLIENT_PID" in
    *[!0-9]* | "") exit 2 ;;
esac
mkdir -p "$RUNTIME"
rm -f "$FIFO"
mkfifo "$FIFO" || exit 1

lipc-wait-event -m com.lab126.powerd goingToScreenSaver > "$FIFO" 2>/dev/null &
WAIT_PID=$!
if IFS= read -r event < "$FIFO"; then
    case "$event" in
        goingToScreenSaver*)
            : > "$RUNTIME/power-exit"
            kill -TERM "$CLIENT_PID" 2>/dev/null || true
            ;;
    esac
fi
