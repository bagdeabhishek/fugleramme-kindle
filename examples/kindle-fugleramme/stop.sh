#!/bin/sh
DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
STATE="$DIR/state"

for PID_FILE in "$STATE/client.pid" /tmp/fugleramme/client.pid; do
    pid=""
    [ -s "$PID_FILE" ] && pid=$(tr -d '\r\n' < "$PID_FILE")
    case "$pid" in
        *[!0-9]* | "") ;;
        *) kill "$pid" 2>/dev/null || true ;;
    esac
    rm -f "$PID_FILE"
done
command -v killall >/dev/null 2>&1 && killall -CONT awesome >/dev/null 2>&1 || true
command -v lipc-set-prop >/dev/null 2>&1 && {
    lipc-set-prop com.lab126.pillow disableEnablePillow enable >/dev/null 2>&1 || true
    lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1 || true
}
command -v lipc-set-prop >/dev/null 2>&1 && \
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1 || true
