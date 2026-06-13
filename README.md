# pi-gen-yarik-os

A focused fork of [pi-gen](pi-gen.md) that builds a single artifact: a **headless,
terminal-only Raspberry Pi OS Lite (arm64) image for the Raspberry Pi Zero 2 W**,
with the [yarik-os](https://github.com/panteleev-ya) C++ HTTP server compiled and
baked straight into the image.

No desktop, no GUI. Just a serial console, Wi-Fi, SSH, apt, the standard Linux
terminal toolset, and our web server listening on port `1337`.

> **Base pi-gen documentation** (stages, config reference, Docker internals,
> troubleshooting) lives in **[pi-gen.md](pi-gen.md)**. This README only covers
> what is specific to *this* project. The desktop stages (`stage3`–`stage5`) have
> been removed; only `stage0`, `stage1`, and `stage2` (Lite) are built.

---

## What's in the image

| Capability | Provided by |
|---|---|
| Serial console over UART @ 115200 | `config.txt` (`enable_uart=1`) + `cmdline.txt` (`console=serial0`) |
| Wi-Fi | `firmware-brcm80211` (Zero 2 W chip) + NetworkManager, `WPA_COUNTRY=US` |
| SSH | `openssh-server`, `ENABLE_SSH=1` |
| Package manager + build tools | `apt`, `build-essential` / `g++`, Python, etc. |
| mDNS | avahi → reachable as `yarikos.local` |
| **yarik-os HTTP server** | compiled in-image, runs as `yarik-app.service` on `:1337` |

Default login: **`yarikp` / `12345`**, hostname **`yarikos`**.

---

## Serial console over UART (`screen`)

The image enables a login console on the Pi's UART at **115200 baud**. You drive
it from your computer with a cheap **USB-to-TTL serial adapter** (CP2102, FTDI,
CH340, …) and `screen`.

### Wiring

Hold the Zero 2 W with the **SD-card slot facing up**. The 40-pin header is now a
vertical strip on the **right**. Look at the **right-hand column** of pins, top to
bottom — the first two are 5 V (skip them), then come the three you need:

```
        ┌─ SD card (up) ─┐
        │                │
        │  ...    2  ●   │  5V    ← skip
        │  ...    4  ●   │  5V    ← skip
        │  ...    6  ●───┼── black   GND
        │  ...    8  ●───┼── yellow  GPIO14 / TXD
        │  ...   10  ●───┼── orange  GPIO15 / RXD
        │  ...           │
        └────────────────┘
            right column ▲ (even pins)
```

| Wire | Pi pin | Pi function | → Adapter pin |
|---|---|---|---|
| **Black** | 6 | GND | GND |
| **Yellow** | 8 | GPIO14 / **TXD** (Pi transmits) | **RX** |
| **Orange** | 10 | GPIO15 / **RXD** (Pi receives) | **TX** |

> ⚠️ **TX↔RX cross over.** The Pi's TX (yellow) goes to the adapter's RX, and the
> Pi's RX (orange) goes to the adapter's TX. If you see nothing, swap those two.
>
> ⚠️ **Do not connect the 5 V pins.** Power the Pi from its own `PWR` USB port.
> Feeding 5 V from the serial adapter while USB power is also attached can
> back-power and damage the board — that's why the two 5 V pins are skipped.

### Connecting

Plug the adapter into your computer, then open the serial port at 115200 baud.

**macOS** (your machine):
```bash
ls /dev/tty.usbserial-* /dev/tty.SLAB_USBtoUART 2>/dev/null   # find the device
screen /dev/tty.usbserial-XXXX 115200
```

**Linux:**
```bash
screen /dev/ttyUSB0 115200
```

Power on the Pi (or press Enter) and you'll get the `yarikos login:` prompt.

To leave `screen`: press **`Ctrl-A`** then **`K`** and confirm `y` (kill the
session), or **`Ctrl-A`** then **`D`** to detach and leave it running.

---

## The baked-in HTTP server

The server (source: [stage2/05-yarik-httpd/files/main.cpp](stage2/05-yarik-httpd/files/main.cpp))
listens on `0.0.0.0:1337` and answers `GET /` with `It is yarik-os!`. It runs on
boot as a sandboxed systemd service.

```bash
# from the Pi, or any machine on the same network:
curl http://yarikos.local:1337/        # -> It is yarik-os!

# manage it:
systemctl status yarik-app
journalctl -u yarik-app
```

---

## Where the custom code lives

Everything that diverges from upstream pi-gen:

| Path | Purpose |
|---|---|
| [config](config) | All build settings (lite-only `STAGE_LIST`, Wi-Fi country, SSH, user, hostname) |
| [stage1/00-boot-files/files/config.txt](stage1/00-boot-files/files/config.txt) | Firmware config — `enable_uart=1` for the serial console |
| [stage2/05-yarik-httpd/](stage2/05-yarik-httpd/) | The custom sub-stage that embeds the HTTP server |
| ├─ `files/main.cpp` | The C++ server source (copied from the yarik-os project) |
| ├─ `files/yarik-app.service` | systemd unit |
| └─ `00-run.sh` | Copies the source in, compiles it, enables the service |

---

## How to add more customizations

Customizations are **sub-stages** inside `stage2/`. Each is a numbered directory
(`NN-name/`) run in ascending order; place yours after `05-` to run last. Within a
sub-stage, pi-gen processes these files (see [pi-gen.md](pi-gen.md) for the full
list):

- `00-packages` — newline/space-separated apt packages to install.
- `00-run.sh` — a shell script run **on the host build machine**. The target
  filesystem is at `${ROOTFS_DIR}`; use the `on_chroot` helper to run commands
  *inside* the image (with the target's arm64 binaries, via QEMU).
- `files/` — assets you copy into the image.

Example — add a tool and a service:

```bash
mkdir -p stage2/06-mytool/files
echo "tmux jq" > stage2/06-mytool/00-packages      # apt installs these
cat > stage2/06-mytool/00-run.sh <<'EOS'
#!/bin/bash -e
install -m 644 files/mytool.service "${ROOTFS_DIR}/etc/systemd/system/"
on_chroot << EOF
systemctl enable mytool.service
EOF
EOS
chmod +x stage2/06-mytool/00-run.sh
```

To compile your own C/C++ in-image, mirror [stage2/05-yarik-httpd/00-run.sh](stage2/05-yarik-httpd/00-run.sh):
copy the source into `${ROOTFS_DIR}` and run `g++` via `on_chroot` (the toolchain
is already present from `stage2/01-sys-tweaks`).

---

## How it's built

pi-gen assembles the root filesystem in **stages**, each layered on top of the
previous, then packages the result into a `.img`:

```
config (STAGE_LIST)
   │
stage0  debootstrap → minimal Debian arm64
   │  rsync rootfs
stage1  bootable: config.txt (UART), cmdline.txt, networking
   │  rsync rootfs
stage2  Lite: ssh · Wi-Fi · apt · g++   ── 05-yarik-httpd compiles & enables the server
   │
EXPORT_IMAGE → deploy/yarikOS.img
```

Builds **must** run on Linux, so on macOS use Docker (Docker Desktop running):

```bash
./build-docker.sh
```

The finished image lands in `deploy/`. To rebuild after a code change without
re-running earlier stages, see the incremental-build notes in [pi-gen.md](pi-gen.md).

### Flashing

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (choose "Use
custom" and select the image from `deploy/`), or `dd` / [`bmaptool`](https://github.com/yoctoproject/bmaptool).
Insert the card, attach the serial adapter as above, power on, and watch the boot
on `screen`.

---

## Project config reference

Key values in [config](config) (full reference in [pi-gen.md](pi-gen.md)):

| Variable | Value | Effect |
|---|---|---|
| `STAGE_LIST` | `stage0 stage1 stage2` | Lite-only; no desktop stages run |
| `IMG_NAME` | `yarikOS` | Output image name |
| `FIRST_USER_NAME` / `FIRST_USER_PASS` | `yarikp` / `12345` | Default login (change before shipping) |
| `ENABLE_SSH` | `1` | SSH server enabled |
| `TARGET_HOSTNAME` | `yarikos` | mDNS name `yarikos.local` |
| `WPA_COUNTRY` | `US` | WLAN regulatory domain (set to your country) |
| `ENABLE_CLOUD_INIT` | `0` | Skips cloud-init seed files |
