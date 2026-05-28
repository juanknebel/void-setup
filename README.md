# Void Linux X61 Tablet Setup

Idempotent provisioning + dotfiles for a ThinkPad X61 Tablet running
**Void Linux** with **i3** (X11) as the desktop environment. All scripts
are modular: pick what you want, skip what you don't.

Themed to Breeze Dark for visual consistency.

For deeper detail on architecture, conventions, and per-script
responsibilities, see [CLAUDE.md](./CLAUDE.md).

---

## Quick start

All scripts support `-d/--dry-run` (preview without changes) and
`-h/--help`. Run them from the repo root.

### Step 0 — Fresh install only

If you are installing on an empty disk from the Void live ISO:

```bash
./setup-disk.sh /dev/sda   # interactive cfdisk (DOS/MBR) + mkfs.ext4 + mount
```

This creates a 512 MB `/boot` partition (ext4, bootable) and a root
partition (ext4) for the rest of the disk. Then run `void-installer`,
pointing it at the mounts already created (do **not** re-format). Pick
GRUB (legacy BIOS) as the bootloader. After installation, reboot into
the new system before continuing.

> Skip Step 0 if you are running these scripts on an existing Void install.

---

### Standard path

```bash
./setup-base.sh         # system foundation (NM, SDDM, audio, BT, fonts, Qt+GTK theming, shell, CLI)
./setup-i3.sh           # i3 WM + polybar, picom, dunst, rofi, flameshot, xclip, feh, etc.
./setup-dotfiles.sh     # user configs (i3, polybar, alacritty, zsh, Xresources, etc.)
```

Reboot and pick **i3** from the SDDM session menu.

---

## Optional add-ons

Run any of these in any order, **after** the path above. Each is
self-contained and idempotent.

| Script | What it does | Flags |
|---|---|---|
| `setup-x61.sh` | X61 Tablet hardware: Wacom driver, thinkfan, TLP, HDAPS disk protection, acpi_call | — |
| `setup-zram.sh` | zram compressed swap (zstd, 50%, prio 32767) + `vm.swappiness=100` | `--with-swapfile` also creates `/swapfile` (prio=10) as OOM backstop |
| `setup-fingerprint.sh` | fprintd + libfprint; verify your reader's USB ID before running | — |

---

## Preview before applying

Every setup script supports `--dry-run`:

```bash
./setup-base.sh --dry-run
./setup-i3.sh --dry-run
./setup-x61.sh --dry-run
./setup-dotfiles.sh --dry-run
```

Dry-run logs every action that would be taken (package installs, service
symlinks, file writes, env-var appends) without touching the system.

---

## Post-install manual steps

### After `setup-x61.sh`

- **Verify Wacom device name** — `xinput list | grep -i wacom`. If the
  name differs from `Wacom ISD`, edit `WACOM_DEVICE` at the top of
  `~/.local/bin/rotate_screen_x11.sh`.
- **Verify rotation keysym** — press the bezel button and run `xev`.
  It should emit `XF86RotateWindows`. If it emits something else, update
  the binding in `~/.config/i3/config`.
- **Tune thinkfan thresholds** — the defaults in `/etc/thinkfan.conf` are
  conservative. Monitor with `cat /proc/acpi/ibm/thermal` under load and
  adjust the levels to suit your unit.

### After `setup-fingerprint.sh`

- **Enroll a fingerprint** — `fprintd-enroll`. Verify with `fprintd-verify`.
- **(Optional) PAM integration** — add as the FIRST auth line to the
  PAM stack you want fingerprint auth on (e.g. `/etc/pam.d/sudo`):
  ```
  auth sufficient pam_fprintd.so
  ```
  ⚠️ Always use `sufficient`, **never** `required` alone (CVE-2024-37408).

### After `setup-zram.sh`

Verify with:
```bash
zramctl                # should show /dev/zram0 with zstd
swapon --show          # zram + (optional) /swapfile with priorities
free -h
```

### Verification quick-reference

```bash
# Audio
pactl info                                              # "PulseAudio (on PipeWire ...)"
pw-play /usr/share/sounds/alsa/Front_Center.wav         # speaker test

# Bluetooth
sudo sv status bluetoothd
bluetoothctl list

# TLP (after setup-x61.sh)
tlp-stat -s

# thinkfan
sudo sv status thinkfan
cat /proc/acpi/ibm/fan

# HDAPS / disk protection
sudo sv status hdapsd

# Wacom tablet
xinput list | grep -i wacom

# i3 + polybar
i3 --version ; polybar --version

# zram (after setup-zram.sh)
zramctl ; swapon --show ; free -h
```

### Hardware notes (X61 Tablet quirks)

- **Boot**: BIOS-only, no UEFI. Disk uses MBR/DOS partition table. GRUB
  installs to the MBR.
- **GPU**: Intel GMA X3100 (965GM). Driver: `mesa` + `modesetting` DDX.
  `mesa-dri` is mandatory; without it SDDM is a black screen. Do **not**
  install `xf86-video-intel` — modesetting performs better on modern kernels.
- **picom**: must use `backend = "xrender"`. The glx backend has rendering
  bugs on the 965GM.
- **Display output**: `LVDS1` in X11/xrandr (not `LVDS-1`).
- **Rotation button**: emits `XF86RotateWindows` (verify with `xev`).
- **Wacom ISD300 digitizer**: pen + eraser, no multitouch. Device name
  varies by firmware — verify with `xinput list`.
- **HDAPS**: the accelerometer is exposed via `thinkpad_acpi` and used
  by `hdapsd` for HDD head parking. Not usable for auto-rotation.
- **Auto-rotation is impossible** from software alone — there is no IIO
  sensor. Rotation is button-only via `rotate_screen_x11.sh`.

---

## Repository layout

```
setup-disk.sh              pre-install partitioning (live ISO, BIOS/MBR)
setup-base.sh              common system foundation
setup-i3.sh                i3 WM + X11 helper stack
setup-dotfiles.sh          user-level dotfiles installer
setup-x61.sh               X61 Tablet hardware add-on
setup-zram.sh              zram + sysctl swap setup
setup-fingerprint.sh       fingerprint reader setup
dotfiles/                  payload copied into ~/.config + ~/.local/bin
images/                    wallpapers copied into ~/Pictures
CLAUDE.md                  internal guidance for AI coding assistants
```
