#!/bin/sh
# BusyBox/POSIX client: check a tiny version, download only a changed frame,
# display it with FBInk, then suspend until the next check where supported.
set -u

DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
CONFIG=${FUGLERAMME_CONFIG:-"$DIR/config.sh"}
# shellcheck disable=SC1090
[ -r "$CONFIG" ] && . "$CONFIG"

FUGLERAMME_URL=${FUGLERAMME_URL:-}
KINDLE_WIDTH=${KINDLE_WIDTH:-}
KINDLE_HEIGHT=${KINDLE_HEIGHT:-}
INTERVAL_SECONDS=${INTERVAL_SECONDS:-300}
START_DELAY_SECONDS=${START_DELAY_SECONDS:-5}
MANAGE_WIFI=${MANAGE_WIFI:-1}
WIFI_WAIT_SECONDS=${WIFI_WAIT_SECONDS:-30}
SUSPEND_MODE=${SUSPEND_MODE:-auto}
RTC_DEVICE=${RTC_DEVICE:-}
FBINK=${FBINK:-}
FREEZE_KINDLE_UI=${FREEZE_KINDLE_UI:-0}
FRONTLIGHT_MODE=${FRONTLIGHT_MODE:-keep}
FRONTLIGHT_LEVEL=${FRONTLIGHT_LEVEL:-5}
FRONTLIGHT_SYSFS=${FRONTLIGHT_SYSFS:-}
UI_FROZEN=0
FRONTLIGHT_CHANGED=0

STATE="$DIR/state"
RUNTIME=${FUGLERAMME_RUNTIME:-$STATE}
FRAME="$STATE/frame.png"
VERSION="$STATE/version"
LOG="$RUNTIME/fugleramme.log"
PID_FILE=${FUGLERAMME_PID_FILE:-"$RUNTIME/client.pid"}
ONCE=0
[ "${1:-}" = "--once" ] && ONCE=1
STOP_REASON=normal

mkdir -p "$STATE" "$RUNTIME"

log() {
    line="$(date '+%Y-%m-%d %H:%M:%S') client $$ $*"
    printf '%s\n' "$line" >> "$LOG" 2>/dev/null || true
    command -v logger >/dev/null 2>&1 && logger -t fugleramme "$line" 2>/dev/null || true
}

fail_config() {
    log "$1"
    exit 2
}

case "$KINDLE_WIDTH" in
    *[!0-9]* | "") fail_config "Set KINDLE_WIDTH to an integer in config.sh" ;;
esac
case "$KINDLE_HEIGHT" in
    *[!0-9]* | "") fail_config "Set KINDLE_HEIGHT to an integer in config.sh" ;;
esac
case "$INTERVAL_SECONDS" in
    *[!0-9]* | "" | 0) fail_config "INTERVAL_SECONDS must be a positive integer" ;;
esac
case "$FRONTLIGHT_MODE" in
    keep | off | fixed) ;;
    *) fail_config "FRONTLIGHT_MODE must be keep, off, or fixed" ;;
esac
case "$FRONTLIGHT_LEVEL" in
    *[!0-9]* | "") fail_config "FRONTLIGHT_LEVEL must be a non-negative integer" ;;
esac
[ -n "$FUGLERAMME_URL" ] || fail_config "Set FUGLERAMME_URL in config.sh"
FUGLERAMME_URL=${FUGLERAMME_URL%/}

if [ -z "$FBINK" ]; then
    for candidate in "$DIR/bin/fbink" /usr/bin/fbink /usr/local/bin/fbink; do
        if [ -x "$candidate" ]; then
            FBINK=$candidate
            break
        fi
    done
fi
if [ -z "$FBINK" ] && command -v fbink >/dev/null 2>&1; then
    FBINK=$(command -v fbink)
fi
[ -x "$FBINK" ] || fail_config "FBInk not found; install it or set FBINK in config.sh"

download() {
    url=$1
    target=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --connect-timeout 10 --max-time 90 -o "$target" "$url" 2>> "$LOG"
        return
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$target" "$url" 2>> "$LOG"
        return
    fi
    return 127
}

wifi_on() {
    [ "$MANAGE_WIFI" = 1 ] || return 0
    command -v lipc-set-prop >/dev/null 2>&1 || return 0
    lipc-set-prop com.lab126.wifid enable 1 >/dev/null 2>&1 || true
    waited=0
    while [ "$waited" -lt "$WIFI_WAIT_SECONDS" ]; do
        if lipc-get-prop com.lab126.wifid cmState 2>/dev/null | grep -q CONNECTED; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 0
}

wifi_off() {
    [ "$MANAGE_WIFI" = 1 ] || return 0
    command -v lipc-set-prop >/dev/null 2>&1 || return 0
    lipc-set-prop com.lab126.wifid enable 0 >/dev/null 2>&1 || true
}

refresh() {
    query="width=$KINDLE_WIDTH&height=$KINDLE_HEIGHT"
    remote_tmp="$STATE/version.tmp"
    frame_tmp="$STATE/frame.tmp"
    rm -f "$remote_tmp" "$frame_tmp"

    if ! download "$FUGLERAMME_URL/kindle/version?$query" "$remote_tmp"; then
        log "Version check failed; keeping the current screen"
        rm -f "$remote_tmp"
        return 1
    fi
    remote=$(tr -d '\r\n' < "$remote_tmp")
    rm -f "$remote_tmp"
    case "$remote" in
        "" | *[!0-9a-f]*) log "Server returned an invalid version"; return 1 ;;
    esac
    current=""
    [ -r "$VERSION" ] && current=$(cat "$VERSION")
    if [ "$remote" = "$current" ] && [ -s "$FRAME" ]; then
        log "Frame unchanged at $remote"
        return 0
    fi

    if ! download "$FUGLERAMME_URL/kindle/frame.png?$query" "$frame_tmp"; then
        log "Frame download failed; keeping the current screen"
        rm -f "$frame_tmp"
        return 1
    fi
    if [ ! -s "$frame_tmp" ]; then
        log "Frame download was empty; keeping the current screen"
        rm -f "$frame_tmp"
        return 1
    fi
    mv "$frame_tmp" "$FRAME"
    if "$FBINK" -q -c -f -i "$FRAME" >> "$LOG" 2>&1; then
        printf '%s\n' "$remote" > "$VERSION"
        log "Displayed frame $remote"
        return 0
    fi
    log "FBInk could not display the downloaded frame"
    return 1
}

find_rtcwake() {
    if command -v rtcwake >/dev/null 2>&1; then
        command -v rtcwake
        return
    fi
    [ -x /usr/sbin/rtcwake ] && printf '%s\n' /usr/sbin/rtcwake
}

ordinary_sleep() {
    remaining=$INTERVAL_SECONDS
    while [ "$remaining" -gt 0 ]; do
        sleep 1
        remaining=$((remaining - 1))
    done
}

pause_until_next_check() {
    [ "$SUSPEND_MODE" != 0 ] || { ordinary_sleep; return; }
    rtcwake=$(find_rtcwake)
    [ -n "$rtcwake" ] || { ordinary_sleep; return; }
    device=$RTC_DEVICE
    if [ -z "$device" ]; then
        [ -e /dev/rtc1 ] && device=/dev/rtc1 || device=/dev/rtc0
    fi
    sync
    if ! "$rtcwake" -d "$device" -m mem -s "$INTERVAL_SECONDS" >> "$LOG" 2>&1; then
        log "rtcwake failed on $device; using an ordinary sleep"
        ordinary_sleep
    fi
}

restore_kindle_ui() {
    [ "$UI_FROZEN" = 1 ] || return 0
    command -v killall >/dev/null 2>&1 && killall -CONT awesome >/dev/null 2>&1 || true
    command -v lipc-set-prop >/dev/null 2>&1 && {
        lipc-set-prop com.lab126.pillow disableEnablePillow enable >/dev/null 2>&1 || true
        lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1 || true
    }
    UI_FROZEN=0
    log "Restored the Kindle UI"
}

freeze_kindle_ui() {
    [ "$FREEZE_KINDLE_UI" = 1 ] || return 0
    command -v lipc-set-prop >/dev/null 2>&1 && \
        lipc-set-prop com.lab126.pillow disableEnablePillow disable >/dev/null 2>&1 || true
    if command -v killall >/dev/null 2>&1 && killall -STOP awesome >/dev/null 2>&1; then
        UI_FROZEN=1
        log "Paused the Kindle UI"
    else
        log "Could not pause the Kindle UI"
    fi
}

find_frontlight_sysfs() {
    if [ -n "$FRONTLIGHT_SYSFS" ] && [ -e "$FRONTLIGHT_SYSFS" ]; then
        printf '%s\n' "$FRONTLIGHT_SYSFS"
        return
    fi
    for candidate in \
        /sys/class/backlight/max77696-bl/brightness \
        /sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity \
        /sys/class/backlight/*/brightness; do
        [ -e "$candidate" ] && { printf '%s\n' "$candidate"; return; }
    done
}

save_frontlight() {
    [ "$FRONTLIGHT_MODE" != keep ] || return 0
    if [ ! -e "$RUNTIME/frontlight.lipc" ] && command -v lipc-get-prop >/dev/null 2>&1; then
        lipc-get-prop -i com.lab126.powerd flIntensity \
            > "$RUNTIME/frontlight.lipc" 2>/dev/null || rm -f "$RUNTIME/frontlight.lipc"
    fi
    node=$(find_frontlight_sysfs)
    if [ ! -e "$RUNTIME/frontlight.sysfs" ] && [ -n "$node" ] && [ -r "$node" ]; then
        cat "$node" > "$RUNTIME/frontlight.sysfs" 2>/dev/null || true
        printf '%s\n' "$node" > "$RUNTIME/frontlight.path" 2>/dev/null || true
    fi
}

set_frontlight() {
    [ "$FRONTLIGHT_MODE" != keep ] || return 0
    save_frontlight
    level=$FRONTLIGHT_LEVEL
    [ "$FRONTLIGHT_MODE" = off ] && level=0
    if command -v lipc-set-prop >/dev/null 2>&1; then
        lipc-set-prop -i com.lab126.powerd flIntensity "$level" >/dev/null 2>&1 || \
            log "Could not set frontlight through powerd"
    fi
    # Older Kindles, including the Paperwhite 3, may leave the LEDs faintly on
    # when powerd is set to zero. KOReader also writes zero to the backlight node.
    if [ "$level" = 0 ]; then
        node=$(find_frontlight_sysfs)
        [ -n "$node" ] && printf '0\n' > "$node" 2>/dev/null || true
    fi
    FRONTLIGHT_CHANGED=1
    log "Set frontlight mode=$FRONTLIGHT_MODE level=$level"
}

restore_frontlight() {
    [ "$FRONTLIGHT_CHANGED" = 1 ] || return 0
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
    FRONTLIGHT_CHANGED=0
    log "Restored the previous frontlight setting"
}

cleanup() {
    status=$?
    trap - EXIT
    log "Stopping with status $status ($STOP_REASON)"
    wifi_on
    restore_frontlight
    restore_kindle_ui
    command -v lipc-set-prop >/dev/null 2>&1 && \
        lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1 || true
    [ "$ONCE" = 1 ] || rm -f "$PID_FILE"
    exit "$status"
}

stopped() {
    signal=$1
    status=$2
    STOP_REASON="signal $signal"
    log "Received $signal"
    exit "$status"
}

trap cleanup EXIT
# HUP is deliberately ignored because KUAL closes after launching the client.
trap '' HUP
trap 'stopped INT 130' INT
trap 'stopped TERM 143' TERM

log "Starting; parent=${PPID:-unknown} url=$FUGLERAMME_URL size=${KINDLE_WIDTH}x${KINDLE_HEIGHT} interval=${INTERVAL_SECONDS}s runtime=$RUNTIME"
sleep "$START_DELAY_SECONDS"
if command -v lipc-set-prop >/dev/null 2>&1; then
    if lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1; then
        log "Prevented the native screen saver"
    else
        log "Could not prevent the native screen saver"
    fi
else
    log "lipc-set-prop is unavailable; native power management remains active"
fi
freeze_kindle_ui
set_frontlight

while :; do
    wifi_on
    refresh || true
    wifi_off
    [ "$ONCE" = 1 ] && exit 0
    pause_until_next_check
done
