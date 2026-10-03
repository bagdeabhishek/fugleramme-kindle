#!/bin/sh
DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PID_FILE="$DIR/state/client.pid"

if [ -r "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    kill "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
fi
command -v killall >/dev/null 2>&1 && killall -CONT awesome >/dev/null 2>&1 || true
command -v lipc-set-prop >/dev/null 2>&1 && {
    lipc-set-prop com.lab126.pillow disableEnablePillow enable >/dev/null 2>&1 || true
    lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1 || true
}
command -v lipc-set-prop >/dev/null 2>&1 && \
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1 || true
