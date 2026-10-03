# Fugleramme for Kindle and KOReader

Turn a jailbroken Kindle or a KOReader device such as Kobo Libra Colour into a
low-power, live BirdNET art frame.

This project extends [Fugleramme](https://github.com/arnegiacomo/fugleramme) with a
resolution-aware display renderer, a tiny Kindle shell client, and a portable
KOReader plugin. Fugleramme stays on a server, where it receives BirdNET-Go
detections and composes the artwork. The e-reader downloads a new fullscreen image
only when the composition changes.

The result is intentionally simple on the e-reader: two small HTTP endpoints, a
POSIX/BusyBox shell script, `curl` or `wget`, and
[FBInk](https://github.com/NiLuJe/FBInk). It supports classic KUAL as well as
KMC/KPM scriptlet launchers.

> [!NOTE]
> This is an independent integration built on Fugleramme. The original project and
> its documentation are by Arne Giacomo. Its README is preserved at
> [docs/FUGLERAMME_UPSTREAM_README.md](docs/FUGLERAMME_UPSTREAM_README.md).

## What it adds

- `GET /kindle/version?width=W&height=H`: a lightweight content/version token.
- `GET /kindle/frame.png?width=W&height=H`: an exact-size, 8-bit grayscale PNG.
- `GET /display/version?width=W&height=H&profile=P`: a portable display token.
- `GET /display/frame.png?width=W&height=H&profile=P`: grayscale or colour PNG.
- Server-side validation and caching for arbitrary Kindle resolutions.
- Download-on-change behavior to reduce Wi-Fi use and flash wear.
- Atomic downloads that retain the last good frame when the network fails.
- Fullscreen rendering with FBInk.
- KUAL Start, Refresh, and Stop actions.
- A KMC/KPM home-screen scriptlet.
- Optional Wi-Fi cycling, ordinary polling, or RTC suspend/wake.
- An optional Kindle 5.x UI pause based on KOReader's reversible
  `pillow`/`awesome` handling.
- Reversible Kindle frontlight control with `keep`, `off`, and `fixed` modes.
- A KOReader plugin with automatic dimensions and colour-screen detection.
- Tests for dimensions, grayscale output, version stability, input validation, and
  authentication boundaries.

## Architecture

```text
microphone -> BirdNET-Go -> Fugleramme server -> version + grayscale PNG -> Kindle
```

Fugleramme owns detection state, layout, artwork, labels, and rendering. The Kindle
only checks a token, fetches a PNG when needed, displays it, and waits.

## Requirements

### Server

- A system capable of running Fugleramme (Linux, Raspberry Pi, VM/LXC, or Docker).
- Python 3.11 or newer when running directly.
- A reachable BirdNET-Go installation or Fugleramme's supported detector setup.

### Kindle

- A jailbroken Kindle.
- KUAL or a KMC/KPM-compatible shell scriptlet launcher.
- FBInk built with image support.
- `curl` or `wget`.
- Wi-Fi access to the Fugleramme server.

The client is model-independent: its width and height are configuration values rather
than compiled assumptions.

### KOReader on Kobo or Kindle

- A working KOReader installation with Wi-Fi access to Fugleramme.
- No FBInk, KUAL, shell launcher, or model-specific resolution is required.

## Server setup

Clone the repository and follow Fugleramme's normal installation path. The original
install, container, hardware, and operations documentation remains available in
[docs/FUGLERAMME_UPSTREAM_README.md](docs/FUGLERAMME_UPSTREAM_README.md) and the
rest of the [`docs/`](docs/) directory.

For local development:

```bash
uv sync
uv run fugleramme-fake-detector
uv run fugleramme-dev
```

The development server listens on port 8080 by default. A production deployment may
publish it directly or through a reverse proxy on port 80.

Verify the Kindle endpoints with a representative screen size:

```bash
curl -fsS \
  'http://SERVER:8080/kindle/version?width=1072&height=1448'

curl -fsS \
  -o kindle.png \
  'http://SERVER:8080/kindle/frame.png?width=1072&height=1448'

file kindle.png
```

The image should report the requested dimensions and grayscale mode.

## Kindle installation

Copy the client directory to USB storage so it appears on the Kindle as:

```text
/mnt/us/extensions/fugleramme/
```

From a Linux workstation where the Kindle is mounted at `/media/$USER/Kindle`:

```bash
mkdir -p "/media/$USER/Kindle/extensions/fugleramme"
cp examples/kindle-fugleramme/config.sh \
   examples/kindle-fugleramme/fugleramme.sh \
   examples/kindle-fugleramme/menu.json \
   examples/kindle-fugleramme/refresh.sh \
   examples/kindle-fugleramme/start.sh \
   examples/kindle-fugleramme/stop.sh \
   "/media/$USER/Kindle/extensions/fugleramme/"
```

For a KMC/KPM launcher, also copy the document scriptlet:

```bash
cp examples/kindle-fugleramme/kmc-launcher.sh \
   "/media/$USER/Kindle/documents/Fugleramme.sh"
sync
```

Do not put a capitalized `Fugleramme.sh` in the extension directory. Kindle
storage is case-insensitive, so it would overwrite the actual
`fugleramme.sh` client.

Safely unmount the Kindle before removing the cable.

## Configuration

Edit `/mnt/us/extensions/fugleramme/config.sh`:

```sh
FUGLERAMME_URL="http://fugleramme.local:8080"
KINDLE_WIDTH=1072
KINDLE_HEIGHT=1448

INTERVAL_SECONDS=300
START_DELAY_SECONDS=5

MANAGE_WIFI=1
WIFI_WAIT_SECONDS=30

SUSPEND_MODE=0
RTC_DEVICE=""

FBINK="/mnt/us/libkh/bin/fbink"
FREEZE_KINDLE_UI=0
FRONTLIGHT_MODE=off
FRONTLIGHT_LEVEL=5
```

Use the LAN URL visible from the Kindle, not `localhost`. Obtain the real display
geometry over SSH with:

```sh
fbink -e
```

### Important options

| Option | Meaning |
|---|---|
| `INTERVAL_SECONDS` | Time between checks; defaults to five minutes |
| `MANAGE_WIFI=1` | Enables Wi-Fi for a check and disables it afterward |
| `MANAGE_WIFI=0` | Leaves Wi-Fi continuously under the Kindle's control |
| `SUSPEND_MODE=0` | Uses ordinary sleep; recommended while testing |
| `SUSPEND_MODE=auto` | Attempts `rtcwake`, then falls back to sleep |
| `START_DELAY_SECONDS` | Lets KUAL/KMC close before the first framebuffer draw |
| `FREEZE_KINDLE_UI=1` | Pauses Kindle 5.x UI repainting while the frame runs |
| `FRONTLIGHT_MODE=keep` | Leaves the existing frontlight unchanged |
| `FRONTLIGHT_MODE=off` | Turns the light off and restores its old level on exit |
| `FRONTLIGHT_MODE=fixed` | Uses `FRONTLIGHT_LEVEL` while the frame is open |

Start with `FREEZE_KINDLE_UI=0`. If the image appears briefly and the Home screen
immediately returns, set it to `1`. `stop.sh` resumes the window manager and status
layer. A forced Kindle restart is the recovery path if cleanup is interrupted.

The Paperwhite 3 can leave a faint glow when only its power service is set to zero.
The `off` mode also writes zero to the detected backlight node, matching KOReader's
handling, and saves both values before changing them. Normal exit and `stop.sh`
restore the saved values.

## KOReader installation for Kobo and Kindle

Copy the complete plugin directory to KOReader:

```text
# Kobo
/mnt/onboard/.adds/koreader/plugins/fugleramme.koplugin/

# Kindle
/mnt/us/koreader/plugins/fugleramme.koplugin/
```

For example, with a Kobo mounted at `/media/$USER/KOBOeReader`:

```bash
mkdir -p "/media/$USER/KOBOeReader/.adds/koreader/plugins"
cp -R examples/koreader-fugleramme/fugleramme.koplugin \
  "/media/$USER/KOBOeReader/.adds/koreader/plugins/"
sync
```

Safely eject the reader, restart KOReader, then choose:

```text
Tools > Fugleramme frame > Set server URL
```

Enter a URL visible from the reader, such as `http://192.168.1.80`, and choose
**Open frame**. Tap the artwork to check immediately. Hold anywhere, or press Back,
to return to KOReader. The plugin reads the live screen width and height. On a Kobo
Libra Colour it automatically requests the `kaleido3` profile; monochrome devices
request `grayscale`. Failed checks retain the cached frame and appear in KOReader's
normal log.

The plugin keeps KOReader in control of suspend, Wi-Fi, frontlight, and colour
rendering. It does not modify Kobo firmware or invoke model-specific shell commands.

## Starting and stopping

With KUAL, choose:

```text
Fugleramme -> Start frame
Fugleramme -> Refresh once
Fugleramme -> Stop frame
```

With KMC/KPM, open the **Fugleramme** document from the Kindle library.

From SSH:

```sh
/bin/sh /mnt/us/extensions/fugleramme/start.sh
/bin/sh /mnt/us/extensions/fugleramme/refresh.sh
/bin/sh /mnt/us/extensions/fugleramme/stop.sh
```

Runtime data and logs are stored under:

```text
/mnt/us/extensions/fugleramme/state/
```

`launcher.log` records KUAL startup, stale PID handling, and early exits.
`fugleramme.log` records the client PID, termination signal, power-management
result, downloads, and framebuffer updates. If the USB storage is read-only,
the launcher uses `/tmp/fugleramme/` and also writes both streams to the Kindle
system log with the `fugleramme` tag.

Force the next cycle to redraw by clearing the cached token:

```sh
: > /mnt/us/extensions/fugleramme/state/version
```

## How each refresh works

1. Bring Wi-Fi up when configured to manage it.
2. Request the small version token.
3. Stop if the token is unchanged and a cached image exists.
4. Download a changed frame to a temporary file.
5. Replace the cache only after a successful, non-empty download.
6. Draw fullscreen through FBInk.
7. Save the version only after FBInk succeeds.
8. Turn Wi-Fi off when configured and wait for the next cycle.

Failures keep the last successfully rendered artwork on the e-ink display.

## Troubleshooting

### The image flashes, then Home returns

Set:

```sh
FREEZE_KINDLE_UI=1
```

Some Kindle 5.x releases keep repainting the native `awesome` window manager over
direct framebuffer applications. This mode temporarily pauses it and disables the
`pillow` UI layer, using the same mechanism as KOReader on affected firmware.

### Wi-Fi repeatedly disconnects

This is expected with `MANAGE_WIFI=1`. Set `MANAGE_WIFI=0` to keep the connection up,
at the cost of additional battery use.

### Nothing updates

Inspect the client log:

```sh
tail -n 100 /mnt/us/extensions/fugleramme/state/launcher.log
tail -n 100 /mnt/us/extensions/fugleramme/state/fugleramme.log
```

If those files did not change, inspect `/tmp/fugleramme/` and the Kindle system
log. A read-only or unavailable `/mnt/us` can prevent KUAL from loading the
extension at all.

Then confirm the Kindle can reach the server URL and that the configured resolution is
numeric.

### The USB volume mounts read-only

Stop and inspect the cable, kernel log, and filesystem state. Always unmount before
disconnecting. Do not run an automatic filesystem repair without a backup and explicit
acceptance that corrupted entries may be recovered or discarded.

## Tests

Run the server test suite with:

```bash
uv run pytest tests/test_server.py tests/test_kindle_client.py tests/test_koreader_plugin.py
```

Run the full project checks with the same commands used by the upstream project and
its CI configuration.

## Documentation

- [Detailed deployment and recovery runbook](docs/DEPLOYMENT_RUNBOOK.md)
- [Kindle and other screen options](docs/screens.md)
- [Original Fugleramme README](docs/FUGLERAMME_UPSTREAM_README.md)
- [Upstream Fugleramme project](https://github.com/arnegiacomo/fugleramme)
- [FBInk](https://github.com/NiLuJe/FBInk)

## Attribution and license

Fugleramme and its application code are copyright their respective contributors and
licensed under the MIT License; see [LICENSE](LICENSE). The bird artwork, fonts,
BirdNET components, and datasets have their own attribution and licensing terms as
documented by the upstream project in
[docs/FUGLERAMME_UPSTREAM_README.md](docs/FUGLERAMME_UPSTREAM_README.md) and the
asset attribution files.

The Kindle integration changes in this repository are provided under the same MIT
license for code. Retain all upstream copyright, license, and artwork attribution when
redistributing the combined project.
