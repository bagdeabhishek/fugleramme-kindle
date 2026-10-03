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
MANAGE_WIFI=${MANAGE_WIFI:-1}
WIFI_WAIT_SECONDS=${WIFI_WAIT_SECONDS:-30}
SUSPEND_MODE=${SUSPEND_MODE:-auto}
RTC_DEVICE=${RTC_DEVICE:-}
FBINK=${FBINK:-}
FREEZE_KINDLE_UI=${FREEZE_KINDLE_UI:-0}
UI_FROZEN=0

STATE="$DIR/state"
FRAME="$STATE/frame.png"
VERSION="$STATE/version"
LOG="$STATE/fugleramme.log"
ONCE=0
[ "${1:-}" = "--once" ] && ONCE=1

mkdir -p "$STATE"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
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
        curl -fsS --connect-timeout 10 --max-time 90 -o "$target" "$url"
        return
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$target" "$url"
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

pause_until_next_check() {
    [ "$SUSPEND_MODE" != 0 ] || { sleep "$INTERVAL_SECONDS"; return; }
    rtcwake=$(find_rtcwake)
    [ -n "$rtcwake" ] || { sleep "$INTERVAL_SECONDS"; return; }
    device=$RTC_DEVICE
    if [ -z "$device" ]; then
        [ -e /dev/rtc1 ] && device=/dev/rtc1 || device=/dev/rtc0
    fi
    sync
    if ! "$rtcwake" -d "$device" -m mem -s "$INTERVAL_SECONDS" >> "$LOG" 2>&1; then
        log "rtcwake failed on $device; using an ordinary sleep"
        sleep "$INTERVAL_SECONDS"
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
}

freeze_kindle_ui() {
    [ "$FREEZE_KINDLE_UI" = 1 ] || return 0
    command -v lipc-set-prop >/dev/null 2>&1 && \
        lipc-set-prop com.lab126.pillow disableEnablePillow disable >/dev/null 2>&1 || true
    if command -v killall >/dev/null 2>&1 && killall -STOP awesome >/dev/null 2>&1; then
        UI_FROZEN=1
        log "Paused the Kindle UI"
    fi
}

cleanup() {
    wifi_on
    restore_kindle_ui
    command -v lipc-set-prop >/dev/null 2>&1 && \
        lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1 || true
    [ "$ONCE" = 1 ] || rm -f "$STATE/client.pid"
}
trap cleanup EXIT
trap 'exit 0' INT TERM
trap '' HUP

command -v lipc-set-prop >/dev/null 2>&1 && \
    lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1 || true
freeze_kindle_ui

while :; do
    wifi_on
    refresh || true
    wifi_off
    [ "$ONCE" = 1 ] && exit 0
    pause_until_next_check
done
