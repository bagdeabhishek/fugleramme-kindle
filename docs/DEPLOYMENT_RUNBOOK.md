# Fugleramme on a Jailbroken Kindle

## Deployment record and operating runbook

This document records the Fugleramme-to-Kindle work completed for this installation,
why each component exists, the problems encountered, and how to operate or recover
the system later.

No passwords are recorded here.

## 1. Resulting system

The installation has three relevant machines:

| Component | Address | Purpose |
|---|---|---|
| Proxmox host | `192.168.1.50` | Hosts the Fugleramme LXC |
| Fugleramme LXC | `192.168.1.80:80` | Web UI and Kindle rendering endpoints |
| BirdNET-Go | `192.168.1.91:80` | Supplies bird detections to Fugleramme |

The Fugleramme container is LXC `112`. Fugleramme is exposed on normal HTTP port
80, so clients use `http://192.168.1.80` without an explicit port.

The Kindle is an Amazon Kindle Paperwhite 3 (2015), serial prefix `G090G1`, with a
native portrait framebuffer of `1072 × 1448` pixels. It is jailbroken with the
KMC/KPM launcher stack and already contains KOReader and an image-capable FBInk at:

```text
/mnt/us/libkh/bin/fbink
```

## 2. Architecture

The Kindle is deliberately a thin client. It does not run Fugleramme or reproduce
the collage layout itself.

```text
BirdNET-Go (192.168.1.91)
          |
          v
Fugleramme LXC (192.168.1.80:80)
  - maintains the bird/collage state
  - renders an exact-size grayscale PNG
  - exposes a small content version
          |
          | HTTP over the LAN
          v
Kindle Paperwhite 3
  - checks the version
  - downloads only when the version changes
  - displays the PNG with FBInk
  - waits or suspends between checks
```

This keeps Kindle-side dependencies and CPU use low. Layout, fonts, bird images,
and visual changes remain controlled by the server.

## 3. Server changes

Two public, read-only routes were added to Fugleramme:

```text
GET /kindle/version?width=<pixels>&height=<pixels>
GET /kindle/frame.png?width=<pixels>&height=<pixels>
```

For this Kindle, the concrete URLs are:

```text
http://192.168.1.80/kindle/version?width=1072&height=1448
http://192.168.1.80/kindle/frame.png?width=1072&height=1448
```

### Version endpoint

`/kindle/version` returns a 16-character hexadecimal token followed by a newline.
The token represents the rendered state at the requested dimensions. The Kindle
compares it with its locally stored version before downloading the much larger PNG.

An observed version during installation was:

```text
f1508128d4f46cc3
```

That value is expected to change when the collage state or requested size changes.

### Frame endpoint

`/kindle/frame.png` renders through Fugleramme's existing page rendering and cache,
then converts the result to an 8-bit grayscale PNG. The verified response was:

```text
PNG image data, 1072 × 1448, 8-bit grayscale, non-interlaced
```

The server validates the requested dimensions:

- each side must be between 320 and 4096 pixels;
- the total image must not exceed 10 megapixels;
- missing and non-numeric dimensions return HTTP 400.

The Kindle routes remain accessible when the Fugleramme admin interface is password
protected. They expose only the same artwork intended for the display, not admin
controls.

### Relevant source files

```text
work/fugleramme/src/fugleramme/web/server.py
work/fugleramme/tests/test_server.py
work/fugleramme/docs/screens.md
work/fugleramme/examples/kindle-fugleramme/
```

Automated tests cover exact dimensions, grayscale mode, stable/changing version
tokens, invalid-size rejection, and accessibility with admin authentication enabled.

## 4. Kindle client files

The installed client lives at:

```text
/mnt/us/extensions/fugleramme/
```

It contains:

| File | Function |
|---|---|
| `config.sh` | Device URL, resolution, timing, Wi-Fi and power settings |
| `fugleramme.sh` | Main POSIX/BusyBox polling and rendering loop |
| `power-exit.sh` | Converts a physical power-button event into a clean exit |
| `start.sh` | Starts one background client and records its PID |
| `refresh.sh` | Performs one immediate check and draw |
| `stop.sh` | Stops the client and restores the Kindle UI |
| `menu.json` | KUAL Start/Refresh/Stop entries |

Because this Kindle uses KMC/KPM rather than classic KUAL, it also has a home-screen
scriptlet:

```text
/mnt/us/documents/Fugleramme.sh
```

Opening the **Fugleramme** document invokes the installed `start.sh`.

Runtime state is written under:

```text
/mnt/us/extensions/fugleramme/state/
```

Important state files are:

| File | Meaning |
|---|---|
| `client.pid` | PID of the background loop |
| `version` | Version currently represented by the cached/displayed frame |
| `frame.png` | Last successfully downloaded image |
| `fugleramme.log` | Client activity and error log |

Downloads use temporary files and are moved into place only after success. If a
version check or image download fails, the previous frame remains displayed.

The client prefers `curl`, falls back to `wget`, validates the version token, and
does not download the image when both the version and cached frame are unchanged.

## 5. Device-specific configuration

The installed Paperwhite 3 configuration is equivalent to:

```sh
FUGLERAMME_URL="http://192.168.1.80"
KINDLE_WIDTH=1072
KINDLE_HEIGHT=1448
INTERVAL_SECONDS=300
START_DELAY_SECONDS=5
FREEZE_KINDLE_UI=1
POWER_BUTTON_EXITS=1
MANAGE_WIFI=1
WIFI_WAIT_SECONDS=30
SUSPEND_MODE=0
RTC_DEVICE=""
FBINK="/mnt/us/libkh/bin/fbink"
FRONTLIGHT_MODE=off
FRONTLIGHT_LEVEL=5
```

### Why these values were selected

- `1072 × 1448` was confirmed from KOReader's own device log, not merely assumed
  from the model name.
- A five-second launch delay lets KMC finish closing before the first framebuffer
  draw.
- `FREEZE_KINDLE_UI=1` is required on this firmware because the native `awesome`
  window manager otherwise repaints the home screen over FBInk. The behavior is
  based on the already-working KOReader wrapper installed on the same Kindle.
- `POWER_BUTTON_EXITS=1` provides an escape while that native UI is paused. One
  physical power-button press restores the client-owned state and returns Home.
- `SUSPEND_MODE=0` is the safe initial setting. The client waits normally rather
  than attempting a model-specific RTC suspend before that path has been tested.
- FBInk uses the copy already supplied by the Kindle's jailbreak environment.
- `FRONTLIGHT_MODE=off` saves the Paperwhite's current power-service and sysfs
  brightness, turns the LEDs fully off, and restores both values when stopped.

## 5a. KOReader path for Kobo Libra Colour

The repository now also contains a device-independent KOReader plugin:

```text
examples/koreader-fugleramme/fugleramme.koplugin/
```

Install it on a Kobo at:

```text
/mnt/onboard/.kobo/koreader/plugins/fugleramme.koplugin/
```

This deployment keeps the complete managed KOReader tree below `.kobo/koreader`
and launches it through NickelMenu. Nickel already ignores `.kobo`, so the install
must not add or rewrite `ExcludeSyncFolders`. Use the guarded installer described
in [Kobo installation safety](kobo-safety.md); it takes host-side metadata backups
and proves that `Kobo eReader.conf` did not change.

Restart KOReader, select **Tools > Fugleramme frame > Set server URL**, enter
`http://192.168.1.80`, and select **Open frame**. It queries KOReader for the actual
screen dimensions and detects the colour panel, so the Libra Colour does not need a
hardcoded resolution. KOReader owns Wi-Fi, suspend, and frontlight behavior.

The shared endpoints are:

```text
GET /display/version?width=<pixels>&height=<pixels>&profile=<profile>
GET /display/frame.png?width=<pixels>&height=<pixels>&profile=<profile>
```

Supported profiles are `grayscale`, `color`, and `kaleido3`. The last two preserve
the server's RGB output; KOReader performs the final device-specific E Ink rendering.
The original `/kindle/*` routes remain unchanged for the shell client.

## 6. Refresh cycle

Each normal loop does the following:

1. Prevents the stock screensaver while the frame client owns the display.
2. Pauses the Kindle UI when `FREEZE_KINDLE_UI=1`.
3. Enables Wi-Fi when `MANAGE_WIFI=1`.
4. Waits up to 30 seconds for Wi-Fi to report `CONNECTED`.
5. Fetches the small version endpoint.
6. If unchanged and a cached frame exists, skips the PNG download and redraw.
7. If changed, downloads the PNG to a temporary file.
8. Uses FBInk for a cleared, forced, fullscreen image update.
9. Saves the new version only after FBInk succeeds.
10. Disables Wi-Fi when `MANAGE_WIFI=1`.
11. Waits 300 seconds and repeats.

## 7. Why Wi-Fi appears to drop

The current disconnection is intentional, not a router fault. With:

```sh
MANAGE_WIFI=1
```

the client enables Wi-Fi only for each check and then disables it for the five-minute
wait. This reduces battery consumption.

To keep Wi-Fi continuously connected, change the setting to:

```sh
MANAGE_WIFI=0
```

This is useful during debugging or when the Kindle is permanently powered. It will
consume more battery. With `MANAGE_WIFI=0`, the client leaves the radio state alone;
Wi-Fi must already be enabled through the Kindle interface.

## 8. Problems encountered and fixes

### USB storage repeatedly mounted read-only

The original USB connection produced USB protocol error `-71`, and the FAT volume
became read-only on its first write. A read-only check could not be performed without
elevated device access, so an explicitly approved repair was run while the volume was
unmounted:

```bash
fsck.vfat -a -v /dev/sdc1
```

The repair reported and reclaimed unconnected clusters. A different USB cable was
then used. The new connection was verified with a complete create, sync, stat, delete,
and sync cycle while the volume remained read-write.

Always unmount the Kindle before disconnecting it. An unsafe cable removal had also
caused a failed SCSI cache synchronization in the host kernel log.

### Frame appeared for less than one second

The client log proved that the image had downloaded and FBInk had rendered it:

```text
Displayed frame f1508128d4f46cc3
```

The image was not missing. The Kindle home interface painted over the framebuffer
immediately afterward.

The first attempt added `START_DELAY_SECONDS=5`, which removed a possible launcher
race but did not stop later native-UI repaints. Inspection of this Kindle's working
KOReader startup wrapper showed the firmware-specific solution:

- disable the `pillow` status/UI layer;
- send `SIGSTOP` to the `awesome` window manager;
- render the third-party framebuffer application;
- send `SIGCONT`, re-enable `pillow`, and open Home during cleanup.

That reversible handling was added behind `FREEZE_KINDLE_UI`. `stop.sh` also performs
the restoration independently, so it can recover the interface even if the client PID
is stale.

## 9. Normal operation

### Start

1. Safely disconnect USB storage.
2. Wait for the Kindle library to refresh.
3. Open the **Fugleramme** document.
4. Wait approximately 5–10 seconds.

The native interface intentionally becomes inactive while Fugleramme controls the
screen. That prevents status bars, clocks, or Home from overwriting the artwork.

### Stop

If KUAL is available, use **Fugleramme → Stop frame**. Over an SSH shell, run:

```sh
/bin/sh /mnt/us/extensions/fugleramme/stop.sh
```

The stop path terminates the loop, resumes `awesome`, re-enables `pillow`, reopens the
Kindle Home app, and re-enables the normal screensaver.

If no shell or launcher is accessible, hold the Kindle power button until the device
restarts. A restart restores the stock window manager and UI services.

### Force a redraw

Using KUAL, choose **Refresh once**. From a shell:

```sh
/bin/sh /mnt/us/extensions/fugleramme/refresh.sh
```

To make the next normal cycle download and display regardless of the cached token:

```sh
: > /mnt/us/extensions/fugleramme/state/version
```

## 10. Diagnostics

### Verify the server from another LAN machine

```bash
curl -fsS \
  'http://192.168.1.80/kindle/version?width=1072&height=1448'

curl -fsS \
  -o kindle.png \
  'http://192.168.1.80/kindle/frame.png?width=1072&height=1448'

file kindle.png
```

Expected properties include `1072 x 1448` and `8-bit grayscale`.

### Inspect the Kindle log

```sh
tail -n 100 /mnt/us/extensions/fugleramme/state/launcher.log
tail -n 100 /mnt/us/extensions/fugleramme/state/fugleramme.log
```

When the user storage cannot be written, the runtime files fall back to
`/tmp/fugleramme/`. The launcher and client also use the system logger with the
tag `fugleramme`. This fallback helps diagnose a newly read-only filesystem, but
KUAL cannot start the extension when `/mnt/us` is unavailable altogether.

Typical useful messages include:

```text
Paused the Kindle UI
Displayed frame <version>
Received TERM
Stopping with status 143 (signal TERM)
Version check failed; keeping the current screen
Frame download failed; keeping the current screen
FBInk could not display the downloaded frame
```

### Check the configured server

```sh
. /mnt/us/extensions/fugleramme/config.sh
printf '%s\n' "$FUGLERAMME_URL"
```

Do not use `localhost` on the Kindle: that would refer to the Kindle itself, not the
LXC.

### Common failure interpretation

| Symptom | Likely cause | Action |
|---|---|---|
| No image and version check failures | Wi-Fi or server unreachable | Check radio, LAN, and `192.168.1.80` |
| Frame flashes, then Home returns | Native Kindle UI was not frozen | Confirm `FREEZE_KINDLE_UI=1` |
| Frame never updates | Cached token unchanged or client not running | Inspect PID/log; clear `state/version` |
| KUAL closes and the client stops | Client shared KUAL's process session | Confirm `setsid` is present; inspect `launcher.log` |
| Logs do not change | User storage is read-only or the extension never launched | Inspect `/tmp/fugleramme`, system log, and filesystem state |
| `FBInk not found` | Configured binary moved or is not executable | Check `/mnt/us/libkh/bin/fbink` |
| Kindle UI remains paused after stopping | Cleanup was interrupted | Run `stop.sh` or restart the Kindle |
| USB volume becomes read-only | Filesystem error or unreliable cable | Safely unmount; inspect host logs; repair only with approval |

## 11. Power-saving path

The client supports `rtcwake` but it is intentionally disabled for initial deployment:

```sh
SUSPEND_MODE=0
```

After the normal polling mode is proven stable, `SUSPEND_MODE=auto` can be tested. In
automatic mode the client uses `rtcwake` if available, preferring `/dev/rtc1` and
falling back to `/dev/rtc0`. If RTC suspend fails, it logs the failure and uses an
ordinary sleep.

Before making RTC suspend permanent, test it over SSH and confirm that this exact
firmware wakes, reconnects Wi-Fi, redraws when required, and leaves a recovery path.

## 12. Reinstalling from USB

The generic source directory is:

```text
work/fugleramme/examples/kindle-fugleramme/
```

The configured copy for this Paperwhite is:

```text
outputs/kindle-device-fugleramme/
```

With the Kindle mounted read-write at `/media/abhishek/Kindle`, the equivalent copy
operation is:

```bash
mkdir -p /media/abhishek/Kindle/extensions/fugleramme
cp outputs/kindle-device-fugleramme/*.sh \
   outputs/kindle-device-fugleramme/menu.json \
   /media/abhishek/Kindle/extensions/fugleramme/
cp work/fugleramme/examples/kindle-fugleramme/kmc-launcher.sh \
   /media/abhishek/Kindle/documents/Fugleramme.sh
sync
```

The source and destination names intentionally differ. FAT is
case-insensitive; `Fugleramme.sh` inside the extension directory would
overwrite its `fugleramme.sh` client.

Then safely unmount before removing the cable:

```bash
udisksctl unmount -b /dev/sdc1
```

Device names such as `/dev/sdc1` can change after reconnecting. Always confirm the
device, label, UUID, and mount point with `lsblk` before running filesystem or mount
commands.

## 13. Current deployment status

Completed and verified:

- Fugleramme is hosted at `192.168.1.80:80`.
- BirdNET-Go is configured at `192.168.1.91:80`.
- The Kindle endpoints return a stable version and correct `1072 × 1448` grayscale
  PNG.
- The Paperwhite model, dimensions, KMC/KPM launcher, and FBInk location were
  identified from the connected device.
- Both KUAL-compatible files and a KMC home-screen scriptlet were installed.
- The FAT filesystem was repaired after explicit approval.
- The replacement cable passed a read/write/sync/delete verification.
- The client log confirmed a successful download and FBInk display.
- Delayed drawing and the KOReader-derived Kindle UI pause/restore behavior were
  installed.

The final UI-pause change was deployed successfully. Its on-device visual result
should be confirmed during the next launch; if it still fails, collect the end of
`state/fugleramme.log` before changing additional settings.
