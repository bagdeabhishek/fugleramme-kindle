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
for RUNTIME in "$STATE" /tmp/fugleramme; do
    if [ -s "$RUNTIME/frontlight.lipc" ] && command -v lipc-set-prop >/dev/null 2>&1; then
        saved=$(tr -d '\r\n' < "$RUNTIME/frontlight.lipc")
        case "$saved" in
            *[!0-9]* | "") ;;
            *) lipc-set-prop -i com.lab126.powerd flIntensity "$saved" >/dev/null 2>&1 || true ;;
        esac
    fi
    if [ -s "$RUNTIME/frontlight.path" ] && [ -s "$RUNTIME/frontlight.sysfs" ]; then
        node=$(tr -d '\r\n' < "$RUNTIME/frontlight.path")
        saved=$(tr -d '\r\n' < "$RUNTIME/frontlight.sysfs")
        case "$saved" in
            *[!0-9]* | "") ;;
            *) case "$node" in
                /sys/class/backlight/* | /sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity)
                    printf '%s\n' "$saved" > "$node" 2>/dev/null || true
                    ;;
            esac ;;
        esac
    fi
    rm -f "$RUNTIME/frontlight.lipc" "$RUNTIME/frontlight.sysfs" "$RUNTIME/frontlight.path"
done
command -v killall >/dev/null 2>&1 && killall -CONT awesome >/dev/null 2>&1 || true
command -v lipc-set-prop >/dev/null 2>&1 && {
    lipc-set-prop com.lab126.pillow disableEnablePillow enable >/dev/null 2>&1 || true
    lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1 || true
}
command -v lipc-set-prop >/dev/null 2>&1 && \
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1 || true
