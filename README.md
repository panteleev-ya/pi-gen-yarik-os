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
| **yarik-os HTTP server** | Bazel-built static aarch64 binary, runs as `yarik-app.service` on `:1337` |

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

The server (source: [apps/yarik-httpd/main.cpp](apps/yarik-httpd/main.cpp))
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

All custom **source code** lives in [`apps/`](apps/) — a self-contained Bazel
workspace, completely separate from the pi-gen stages. The stages never contain
source or a compiler; they only consume the pre-built binary from `dist/`.

| Path | Purpose |
|---|---|
| [`apps/`](apps/) | Bazel workspace for all custom programs (separate from stages) |
| ├─ [`yarik-httpd/main.cpp`](apps/yarik-httpd/main.cpp) | The C++ HTTP server source |
| ├─ `yarik-httpd/BUILD.bazel` | `cc_binary(name = "yarik-app")` |
| ├─ `toolchain/`, `platforms/` | aarch64 (Cortex-A53) cross-compile toolchain & target platform |
| ├─ `docker/Dockerfile` | Builder image: Bazelisk + `aarch64-linux-gnu` cross compiler |
| └─ `MODULE.bazel`, `.bazelrc` | Bazel config (defaults to a static aarch64 `-c opt` build) |
| [`scripts/build-apps.sh`](scripts/build-apps.sh) | Runs Bazel-in-Docker, stages the binary into `dist/` |
| `dist/yarik-app` | Built artifact (gitignored); the only thing the stage installs |
| [stage2/05-yarik-httpd/](stage2/05-yarik-httpd/) | Thin stage: installs `dist/yarik-app` + enables the service |
| ├─ `00-run.sh` | Copies the binary into the rootfs, `systemctl enable` |
| └─ `files/yarik-app.service` | systemd unit |
| [config](config) | All build settings (lite-only `STAGE_LIST`, Wi-Fi country, SSH, user, hostname) |
| [stage1/00-boot-files/files/config.txt](stage1/00-boot-files/files/config.txt) | Firmware config — `enable_uart=1` for the serial console |

---

## How to add more customizations

### Adding a compiled program (Bazel)

1. **Add the source** under `apps/`, e.g. `apps/mytool/{main.cpp, BUILD.bazel}`:
   ```python
   # apps/mytool/BUILD.bazel
   cc_binary(
       name = "mytool",
       srcs = ["main.cpp"],
       visibility = ["//visibility:public"],
   )
   ```
   It cross-compiles to a static aarch64 binary with the shared
   [`apps/toolchain`](apps/toolchain/) — no extra setup needed.

2. **Stage the artifact** by adding it to [`scripts/build-apps.sh`](scripts/build-apps.sh)
   (build `//mytool:mytool` and `install` it into `dist/`).

3. **Embed it** with a thin sub-stage, mirroring
   [stage2/05-yarik-httpd/00-run.sh](stage2/05-yarik-httpd/00-run.sh): install
   `${BASE_DIR}/dist/mytool` into `${ROOTFS_DIR}` and `systemctl enable` any
   service. Stages hold **no source code** — only this install glue.

### Adding OS-level config (no compilation)

Sub-stages are numbered directories inside `stage2/` (`NN-name/`), run in
ascending order — place yours after `05-` to run last. pi-gen processes (full
list in [pi-gen.md](pi-gen.md)):

- `00-packages` — newline/space-separated apt packages to install.
- `00-run.sh` — a host-side script. The target rootfs is `${ROOTFS_DIR}`; use the
  `on_chroot` helper to run commands *inside* the image (target aarch64 binaries
  via QEMU).
- `files/` — assets you copy into the image.

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

---

## How it's built

The build has **two phases** — compile the apps, then build the image. Both run
in Docker (required on macOS; have Docker running):

```bash
make app      # 1. Bazel cross-compiles apps/ → dist/yarik-app (static aarch64)
make image    # 2. pi-gen builds the image, embedding dist/yarik-app → deploy/
make          # both, in order
```

**Phase 1 — `make app`** ([scripts/build-apps.sh](scripts/build-apps.sh)): builds
the `apps/docker` builder image (Bazelisk + `aarch64-linux-gnu` cross compiler),
then runs `bazel build` to produce a static aarch64 binary, staged into `dist/`.
Bazel/download caches persist in `.cache/`.

**Phase 2 — `make image`**: pi-gen assembles the rootfs in **stages**, each
layered on the previous, then packages a `.img`:

```
config (STAGE_LIST)
   │
stage0  debootstrap → minimal Debian arm64
   │  rsync rootfs
stage1  bootable: config.txt (UART), cmdline.txt, networking
   │  rsync rootfs
stage2  Lite: ssh · Wi-Fi · apt   ── 05-yarik-httpd installs dist/yarik-app + enables service
   │
EXPORT_IMAGE → deploy/yarikOS.img
```

The finished image lands in `deploy/`. `make image` depends on `app`, so the
binary is always (re)built and staged into `dist/` first — Bazel is incremental,
so it's a no-op when unchanged. Running `./build-docker.sh` directly skips the
app phase and hard-fails in `stage2/05-yarik-httpd` if `dist/yarik-app` is
missing — use `make` (or `make app`) instead. For incremental pi-gen rebuilds,
see [pi-gen.md](pi-gen.md).

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
