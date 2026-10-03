#!/bin/sh
# shellcheck disable=SC2034
# Fugleramme server as seen from the Kindle. Do not use localhost here.
FUGLERAMME_URL=${FUGLERAMME_URL:-}

# Visible screen size in the orientation in which the Kindle will hang.
# Run `fbink -e` over SSH to inspect the display, then set these two values.
KINDLE_WIDTH=${KINDLE_WIDTH:-}
KINDLE_HEIGHT=${KINDLE_HEIGHT:-}

# Five minutes is responsive without keeping Wi-Fi up continuously.
INTERVAL_SECONDS=${INTERVAL_SECONDS:-300}

# Give KUAL/KMC time to close before FBInk paints the first frame. Without
# this delay the launcher may repaint the home screen over the image.
START_DELAY_SECONDS=${START_DELAY_SECONDS:-5}

# Some Kindle 5.x firmwares repaint the native home UI over FBInk. Set this to
# 1 to pause that UI while Fugleramme runs; stop.sh restores it.
FREEZE_KINDLE_UI=${FREEZE_KINDLE_UI:-0}

# 1 toggles Wi-Fi around each check. Set to 0 if another service manages it.
MANAGE_WIFI=${MANAGE_WIFI:-1}
WIFI_WAIT_SECONDS=${WIFI_WAIT_SECONDS:-30}

# auto uses rtcwake when present and falls back to an ordinary sleep. Set to 0
# while testing, or set RTC_DEVICE explicitly when the automatic choice is wrong.
SUSPEND_MODE=${SUSPEND_MODE:-auto}
RTC_DEVICE=${RTC_DEVICE:-}

# Leave blank to find fbink on PATH or in the extension's bin directory.
FBINK=${FBINK:-}
