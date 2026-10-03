# Screens

Fugleramme serves the collage over HTTP, so it can show on more than the e-ink
panel. Five ways, easiest first.

## From another device

Open `http://<host>.local:8080/` on a phone, tablet or laptop on the same
network. This will work on any Raspberry pi os and installation method.

## On a jailbroken Kindle

A jailbroken Kindle can be a low-power grayscale Fugleramme frame. Fugleramme
does the rendering. The Kindle checks a small version endpoint, downloads a new
PNG only when the page changes, shows it with FBInk, and sleeps between checks.

You need KUAL or a KMC/KPM scriptlet launcher, and an FBInk build with image
support installed on the Kindle.
Copy [`examples/kindle-fugleramme`](https://github.com/arnegiacomo/fugleramme/tree/main/examples/kindle-fugleramme)
to the Kindle over USB so it ends up at:

```text
/mnt/us/extensions/fugleramme/
```

Over SSH, ask FBInk for the display details:

```bash
fbink -e
```

Edit `/mnt/us/extensions/fugleramme/config.sh`. Set `FUGLERAMME_URL` to the
Fugleramme server's LAN address, and set `KINDLE_WIDTH` and `KINDLE_HEIGHT` to
the visible size reported by FBInk in the orientation you want to use. For
example:

```sh
FUGLERAMME_URL="http://192.168.1.20:8080"
KINDLE_WIDTH=1072
KINDLE_HEIGHT=1448
```

The server can be checked from another machine before starting the Kindle:

```bash
curl "http://192.168.1.20:8080/kindle/version?width=1072&height=1448"
curl -o kindle.png "http://192.168.1.20:8080/kindle/frame.png?width=1072&height=1448"
```

Make the launchers executable, disconnect USB storage, open KUAL, and choose
**Fugleramme > Start frame**:

```bash
chmod +x /mnt/us/extensions/fugleramme/*.sh
```

On KMC/KPM-based jailbreaks, also copy `kmc-launcher.sh` to
`/mnt/us/documents/Fugleramme.sh`. Do not put that capitalized destination in
the extension folder: Kindle storage is case-insensitive and it would
overwrite the `fugleramme.sh` client. After disconnecting USB and refreshing
the library, launch the **Fugleramme** document from the Kindle home screen.

The default interval is five minutes. Wi-Fi is enabled only for each check.
The launcher waits five seconds before the first draw so the Kindle home screen
cannot immediately paint over it; tune `START_DELAY_SECONDS` if a launcher on a
particular firmware closes more slowly.
If the stock Kindle interface still paints over the image, set
`FREEZE_KINDLE_UI=1`. This uses the same reversible window-manager pause as
KOReader. **Stop frame** resumes the UI; a forced Kindle restart also restores
it if the client is interrupted unexpectedly.
The script uses `rtcwake` and `/dev/rtc1` when they are available, then falls
back to an ordinary sleep if suspend is unavailable. Kindle RTC devices vary by
model. Test first with `SUSPEND_MODE=0`; once fetching and FBInk work, change it
to `auto`. Set `RTC_DEVICE=/dev/rtc0` in `config.sh` if that is the working RTC
on your model.

**Stop frame** restores the normal screensaver and leaves the last picture on
the display. Logs, the cached frame and the last version are under
`/mnt/us/extensions/fugleramme/state/`. `launcher.log` covers KUAL startup and
PID handling; `fugleramme.log` covers signals, power management, downloads, and
FBInk. If that directory is read-only, runtime logs and the PID fall back to
`/tmp/fugleramme/` and messages are also sent to the system logger. Delete
`state/version` to force the next check to download and redraw the page.

## On HDMI, Raspberry Pi OS Desktop

The desktop OS already has a browser and a session to run it in:

```bash
chromium --kiosk http://localhost:8080/
```

To start it with the desktop, add the same line to `~/.config/labwc/autostart`
(create the file if it isn't there):

```bash
chromium --kiosk http://localhost:8080/ &
```

> [!NOTE]
> The package is `chromium` on Trixie. Older guides say `chromium-browser`,
> which is now an empty package that pulls in `chromium` anyway.

## On HDMI, Raspberry Pi OS Lite

Lite has no browser **and no display server**, so installing `chromium` on its
own is not enough. It needs a compositor and a
session too. [`cage`](https://www.hjdskes.nl/projects/cage/) is the smallest one
that will do: it runs a single app fullscreen and has nothing to configure.

```bash
ssh <user>@<host>.local
sudo apt install --no-install-recommends chromium cage
```

Then a service, so it comes up with the Pi. `PAMName` and `TTYPath` are what
give the browser a login session and a seat on the screen, which is the part
that is missing on Lite:

```bash
sudo tee /etc/systemd/system/fugleramme-kiosk.service <<'EOF'
[Unit]
Description=Fugleramme HDMI kiosk
After=systemd-user-sessions.service getty@tty1.service fugleramme-frame.service
Conflicts=getty@tty1.service

[Service]
User=<user>
PAMName=login
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
StandardInput=tty-force
Environment=XDG_RUNTIME_DIR=/run/user/%U
ExecStart=/usr/bin/cage -- /usr/bin/chromium --kiosk --ozone-platform=wayland --noerrdialogs --disable-infobars http://localhost:8080/
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl disable getty@tty1.service
sudo systemctl enable --now fugleramme-kiosk
```

Replace `<user>` with your username, and `8080` with `FRAME_PORT` if you changed
it.

Disabling `getty@tty1` is not optional. Without it the login prompt and the
kiosk are both pulled in by the same boot transaction, systemd drops one of the
two conflicting jobs, and often it is the kiosk - which starts fine by hand and
then doesn't come back after a reboot.

> [!IMPORTANT]
> This gives up the login prompt on the attached screen, so SSH becomes the only
> way in. `sudo systemctl enable getty@tty1.service` puts it back.

Logs, when it doesn't come up:

```bash
journalctl -u fugleramme-kiosk -f
```

> [!NOTE]
> A portrait screen is rotated by the display, not by the frame. The
> **Rotation** setting on the admin page changes the shape of the page, or
> **Portrait** does with **Lock to panel** off, and only the e-ink panel turns
> its own pixels; for HDMI, rotate the output in
> `/boot/firmware/cmdline.txt` (e.g. `video=HDMI-A-1:1920x1080@60,rotate=90`).

## On a Samsung Frame TV

Courtesy of Conrad Jackson ([@conradj](https://github.com/conradj)):
[fugleramme-samsung-frame](https://github.com/conradj/fugleramme-samsung-frame)
sends the collage to a Samsung Frame TV while it is in Art Mode. It runs next
to the frame and checks for a new collage every 15 minutes. Setup is in that
repo's README.

The TV only offers its own mats when the picture is exactly its size. For
that, turn off **Lock to panel** on the admin page and set **Resolution** to 4K
and **Aspect** to 16:9. Set [Margin](frame.md#margin) to 0 too, since the TV
adds its own mat - with an e-ink panel beside it, turn off **Uniform** first, so the panel keeps its own margin.

![A Samsung Frame showing a Fugleramme collage among framed artwork in a living room](assets/samsung-frame-room.jpg)

![Close-up of the collage on the Samsung Frame](assets/samsung-frame-tv.jpg)

Photos by Conrad Jackson, from
[Fugleramme for Samsung Frame TV](https://github.com/arnegiacomo/fugleramme/discussions/145).

## As a desktop wallpaper and/or screensaver (MacOs)

Turn off **Lock to panel** on the admin page and
set **Resolution** and **Aspect** to match your screen, then:

```bash
curl -fsSL https://raw.githubusercontent.com/arnegiacomo/fugleramme/main/examples/wallpaper-macos.sh | sh -s -- http://<your-fugleramme-address>:8080
```

Add `--every x` after the address to fetch every x minutes (default 15).
The five last rendered pages stay in `~/Pictures/Fugleramme`.

![A MacBook with the collage as its desktop picture](assets/macos-desktop.jpg)

For the screen saver, open System Settings, Screen Saver, set **Use Screen Saver** to Custom and pick **Photos** under Other. Under **Options**, choose the Fugleramme-folder as the source. The screen saver reads the folder when it starts and will shuffle between the 5 last renders.

![The screen saver settings: Photos under Other, then Options, Source and Choose Folder](assets/macos-screen-saver.jpg)


It should look something like:
<video src="../assets/macos-screen-saver.mp4" autoplay loop muted playsinline width="360" aria-label="The screen saver crossfading from one collage to the next on a MacBook"></video>

Not set fugleramme up yourself yet? Point it at a demo, `https://fugleramme.arnegiacomo.dev` or any [showcase](showcase.md) address.

Run this to disable:
```Bash
sh examples/wallpaper-macos.sh --remove
```

![The collage on the lock screen of a MacBook](assets/macos-lock-screen.jpg)
