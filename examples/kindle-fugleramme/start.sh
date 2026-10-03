#!/bin/sh
DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
STATE="$DIR/state"
mkdir -p "$STATE"

runtime_dir() {
    probe="$STATE/.write-test.$$"
    if : > "$probe" 2>/dev/null; then
        rm -f "$probe"
        printf '%s\n' "$STATE"
        return
    fi
    fallback=/tmp/fugleramme
    mkdir -p "$fallback" 2>/dev/null || return 1
    printf '%s\n' "$fallback"
}

RUNTIME=$(runtime_dir) || exit 1
PID_FILE="$RUNTIME/client.pid"
LAUNCH_LOG="$RUNTIME/launcher.log"

notice() {
    line="$(date '+%Y-%m-%d %H:%M:%S') launcher $$ $*"
    printf '%s\n' "$line" >> "$LAUNCH_LOG" 2>/dev/null || true
    command -v logger >/dev/null 2>&1 && logger -t fugleramme "$line" 2>/dev/null || true
}

pid=""
[ -s "$PID_FILE" ] && pid=$(tr -d '\r\n' < "$PID_FILE")
case "$pid" in
    *[!0-9]* | "")
        [ -e "$PID_FILE" ] && notice "discarding invalid PID file: $pid"
        rm -f "$PID_FILE"
        ;;
    *)
        if kill -0 "$pid" 2>/dev/null; then
            notice "already running as PID $pid"
            exit 0
        fi
        notice "discarding stale PID $pid"
        rm -f "$PID_FILE"
        ;;
esac

notice "starting from $DIR with runtime state in $RUNTIME"
# A new session keeps KUAL from terminating the long-running client when its
# launcher closes. Older BusyBox builds may lack setsid; nohup is the fallback.
if command -v setsid >/dev/null 2>&1; then
    FUGLERAMME_RUNTIME="$RUNTIME" FUGLERAMME_PID_FILE="$PID_FILE" \
        setsid /bin/sh "$DIR/fugleramme.sh" </dev/null >/dev/null 2>&1 &
elif command -v nohup >/dev/null 2>&1; then
    FUGLERAMME_RUNTIME="$RUNTIME" FUGLERAMME_PID_FILE="$PID_FILE" \
        nohup /bin/sh "$DIR/fugleramme.sh" </dev/null >/dev/null 2>&1 &
else
    FUGLERAMME_RUNTIME="$RUNTIME" FUGLERAMME_PID_FILE="$PID_FILE" \
        /bin/sh "$DIR/fugleramme.sh" </dev/null >/dev/null 2>&1 &
fi
pid=$!
if ! printf '%s\n' "$pid" > "$PID_FILE"; then
    notice "could not write PID $pid to $PID_FILE"
    kill "$pid" 2>/dev/null || true
    exit 1
fi
sleep 1
if kill -0 "$pid" 2>/dev/null; then
    notice "started PID $pid"
    exit 0
fi
notice "PID $pid exited during startup"
rm -f "$PID_FILE"
exit 1
