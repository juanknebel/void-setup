# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Provisioning + dotfiles for a **ThinkPad X61 Tablet running Void Linux + i3 (X11)**, themed to Breeze Dark for visual consistency. Not a generic dotfiles repo — many design decisions are X61-specific (see "Hardware-specific gotchas" below).

## Common commands

All setup scripts are idempotent and support `--dry-run` for previews. There are **no build/lint/test commands** — this is a config repo.

```bash
# Pre-install (run only on a fresh disk, from the live ISO; needs root)
./setup-disk.sh /dev/sda          # interactive cfdisk + automated mkfs/mount (BIOS/MBR)

# After void-installer + first boot
./setup-base.sh                   # common base (NM, SDDM, audio, BT, fonts, Qt/GTK theming, shell, CLI)

# Desktop
./setup-i3.sh                     # i3 WM + helpers (polybar, picom, dunst, rofi, flameshot, etc.)

# User configs (copies dotfiles/ + images/ into $HOME; i3-focused)
./setup-dotfiles.sh

# Hardware add-ons
./setup-x61.sh                    # X61 Tablet hardware (Wacom, thinkfan, TLP, HDAPS, acpi_call)
                                  #   --ssd / --hdd to skip/force hdapsd (else prompts; disk autodetected)
./setup-zram.sh                   # zram swap (zstd, 50%, prio 32767) + swappiness=100
./setup-fingerprint.sh            # fprintd + libfprint (check USB ID before relying on this)
```

Every script supports `-d/--dry-run` and `-h/--help`.

## Architecture

The repo is a layered set of standalone scripts. Each script is independently runnable and idempotent.

```
setup-disk.sh         (pre-install, in live ISO — BIOS/MBR layout)
       ↓
   [void-installer, reboot]
       ↓
setup-base.sh         (common system: NM/SDDM/audio/BT/fonts/Qt/GTK/shell/CLI)
       ↓
setup-i3.sh           (i3 WM + X11 helper stack)
       ↓
setup-dotfiles.sh     (user configs: i3, polybar, dunst, picom, rofi, alacritty, zsh)
       ↓
[optional: setup-x61.sh, setup-zram.sh, setup-fingerprint.sh]
```

Per-script responsibilities:

- **`setup-disk.sh`** = pre-install only. BIOS/MBR layout: 512MB /boot (ext4, bootable) + rest as / (ext4). No EFI partition. Runs cfdisk interactively, then automates mkfs.ext4 + mount under `/mnt`. Guards: refuses if partitions mounted, requires root, requires `yes` confirmation before mkfs.
- **`setup-base.sh`** = system foundation (needs sudo). Installs packages for NM/SDDM/audio/BT/input/fonts/shell/CLI/Qt+GTK-theming/apps, sets up runit service symlinks (including `acpid` for laptop ACPI events), configures SDDM theme to Breeze, links PipeWire system configs + user autostart, appends `QT_QPA_PLATFORMTHEME=qt6ct` to `/etc/environment`, and sets the TTY console keymap to `la-latin1` (Spanish - Latin American) in `/etc/rc.conf`.
- **`setup-i3.sh`** = i3 compositor additions. Validates base prerequisites first. Adds the X11 WM stack: i3, polybar, picom, dunst, rofi, flameshot, xclip, feh, xrandr, xinput, xautolock, brightnessctl, pulsemixer, bluetui. Also writes `/etc/X11/xorg.conf.d/00-keyboard.conf` setting the X11 keyboard layout to `latam` (Spanish - Latin American), applied to both the SDDM greeter and the i3 session.
- **`setup-dotfiles.sh`** = user-level (no sudo). Copies payload from `dotfiles/` and `images/` into `~/.config/`, `~/.local/bin/`, `~/Pictures/`. Uses `install_file` with timestamp backups.
- **`setup-x61.sh`** = optional X61 Tablet hardware. Installs xf86-input-wacom, libwacom, linuxconsoletools (for `inputattach`), tlp, thinkfan, acpi_call-dkms (+ dkms, linux-headers), and — only on a spinning HDD — hdapsd. Writes `/etc/X11/xorg.conf.d/70-wacom.conf`, `/etc/thinkfan.conf`, `/etc/tlp.conf`, `/etc/modules-load.d/acpi_call.conf`, `/etc/modules-load.d/wacom-serial.conf`. Authors the `wacom-digitizer` runit service (runs `inputattach` for the serial pen). Enables runit services: tlp, thinkfan, wacom-digitizer, and hdapsd (HDD only). Asks SSD/HDD interactively (disk type autodetected as the default), or use `--ssd`/`--hdd` to answer non-interactively; on SSD it skips hdapsd and removes any stale `/var/service/hdapsd`.
- **`setup-zram.sh`** = optional. Same as main branch — hardware-agnostic.
- **`setup-fingerprint.sh`** = optional. Same as main branch — verify your USB ID before relying on it.

All scripts follow the same shape: `set -euo pipefail`, color-coded `log_*` helpers, `--dry-run`/`--help` flags, idempotent xbps package check loop, sudo keep-alive in non-dry-run mode.

## Conventions worth knowing

### Language

**All comments, documentation, commit messages, and any text inside files in this repo MUST be in English**, regardless of file type (configs, shell scripts, dotfiles, `.gitignore`, markdown, etc.). The user's chat language is Spanish but the codebase is English-only. When editing existing files, translate any Spanish text encountered to English in the same pass.

### i3 config

- `;` has no special meaning in i3 config. Multi-command exec uses `sh -c '...'`.
- The `sleep 0.3` in `exec_always` guards avoid a cold-boot race where i3 fires helpers before the X session is fully initialized.
- Panel output is **`LVDS-1`** on the X61 (with a dash). The repo uses the **modesetting** DDX driver, which exposes KMS connector names (`LVDS-1`); the dashless `LVDS1` is the old `xf86-video-intel` convention and is NOT what this setup reports. Verify with `xrandr --query | grep -w connected`.
- Rotation button on the bezel emits **`XF86RotateWindows`** (different from X220's `XF86TaskPane`). Also bound to `Mod+Shift+R` as keyboard equivalent.
- Multimedia/lock bindings use `wpctl` (from wireplumber) and `brightnessctl`.
- Floating TUI popups use `alacritty --class <name>,Alacritty` + `for_window [instance="<name>"]` in i3 config.
- **Keyboard layout is Spanish (Latin American), set in two separate layers with different names:** the X11 layout is **`latam`** (`/etc/X11/xorg.conf.d/00-keyboard.conf`, from `setup-i3.sh` — covers SDDM + i3); the console/TTY keymap is **`la-latin1`** (`KEYMAP` in `/etc/rc.conf`, from `setup-base.sh`). They are distinct subsystems — changing one does not affect the other. Apply live without relogin/reboot: `setxkbmap latam` (X11) / `sudo loadkeys la-latin1` (TTY).

### Shells

- **System shell stays `bash`**. `chsh` is intentionally NOT performed.
- alacritty launches `zsh -l` via its own config — terminals open zsh, TTYs/scripts/SSH stay on bash.
- Scripts with `#!/bin/sh` (powermenu.sh, rotate_screen_x11.sh, lock.sh, polybar/launch.sh) run under **dash** on Void. Use `printf`, not `echo -e` (dash prints `-e` literally as the first arg).

### Color palette (strict Breeze Dark)

| Role | Hex | Where |
|---|---|---|
| Plasma View bg | `#232629` | i3 client bg, polybar, dunst, rofi, i3lock |
| Plasma Window bg | `#31363b` | rofi selection bg |
| Konsole bg | `#232627` | alacritty only |
| Accent / selection | `#3daee9` | focus border, active workspace, dunst frame |
| Muted fg | `#7f8c8d` | inactive text, unfocused borders |
| Border alt | `#4d4d4d` | inactive borders, polybar separator |
| Urgent | `#ed1515` | client.urgent, battery critical |

Don't introduce non-Breeze colors.

### Qt/GTK apps

Qt theming relies on `QT_QPA_PLATFORMTHEME=qt6ct` (set by `setup-base.sh`).
GTK theming: `GTK_THEME=Breeze-Dark` is exported from `~/.xprofile`, which SDDM sources before launching i3.

## Hardware-specific gotchas (X61 Tablet)

These affect script defaults; flagging the non-obvious ones:

- **BIOS-only, no UEFI** — `setup-disk.sh` creates a DOS/MBR partition table, not GPT. No EFI partition. GRUB is installed to the MBR by void-installer.
- **mesa-dri** is mandatory; without it SDDM shows a black screen on the Intel GMA X3100 (965GM / i965).
- **modesetting DDX driver is preferred** over `xf86-video-intel` for the GMA X3100 on modern kernels. Do not install `xf86-video-intel` unless you're troubleshooting specific artifacts.
- **picom uses `backend = "xrender"`** — the glx backend has rendering bugs on the 965GM chipset. Do not switch to glx.
- **elogind** is mandatory for SDDM session management on Void, even under X11.
- **libspa-bluetooth** is needed for BT audio.
- **Wacom serial digitizer (pen)** — this is a **serial ISDv4/W8001 device**, not USB. The kernel does **not** auto-attach it: `xinput` shows nothing until `inputattach --baud 19200 --w8001 /dev/ttyS0` runs and `wacom_w8001` binds the resulting serio port. `setup-x61.sh` handles this via the `wacom-digitizer` runit service (forces `serport` + `wacom_w8001` modules, then runs inputattach with a retry loop because the cold-port W8001 probe occasionally misses). Confirmed facts on this unit: port **`/dev/ttyS0`**, baud **19200**, BIOS PNP id **`WACf004`**, and the pen reports as **`Wacom Serial Penabled Pen`** (with `stylus`/`eraser` subdevices once `xf86-input-wacom` attaches) — **not** `Wacom ISD`. The X11 InputClass and `rotate_screen_x11.sh` both match the broad `Wacom` substring. If `inputattach` ever fails with `can't set device type`, the `serport` module isn't loaded. Bring the pen up without a reboot: `sudo sv up wacom-digitizer`. Only `/dev/ttyS0` is a real UART on the X61 (ttyS1-3 error on attach).
- **LVDS-1** (with dash) is the xrandr output name under the modesetting driver. Hardcoded in `rotate_screen_x11.sh`.
- **XF86RotateWindows** is the rotation button keysym on the X61 (not `XF86TaskPane` which is X220-specific). Verify with `xev` if the button doesn't respond.
- **No IIO accelerometer** — rotation is manual-only via bezel button + script.
- **acpi_call kernel module** for battery charge thresholds — Void has no plain `acpi_call` package, only `acpi_call-dkms`, so `setup-x61.sh` installs that plus `dkms` and `linux-headers` (DKMS builds the module against the running kernel). `/etc/modules-load.d/acpi_call.conf` loads it on next reboot. If you boot a non-default kernel series (e.g. `linux-lts`), install its matching `-headers` and run `dkms autoinstall`. Verify with `dkms status acpi_call`.
- **thinkfan** reads `/proc/acpi/ibm/thermal` for temperatures. The conservative defaults in `setup-x61.sh` may need tuning for your specific unit.
- **HDAPS accelerometer** is exposed under `/sys/devices/platform/thinkpad_acpi` and used by `hdapsd` for HDD head parking on shock. Not related to screen rotation. **SSD-gated:** hdapsd only protects spinning disks, so `setup-x61.sh` installs/enables it only when the machine has an HDD (asked interactively, autodetected from `/sys/block/*/queue/rotational`, or forced with `--hdd`/`--ssd`). On an SSD it would find no rotating disk and exit, causing a runit restart loop — hence the gate. The Void `hdapsd` package ships **no runit service**, so the script authors `/etc/sv/hdapsd/run` itself (`exec hdapsd`; foreground, autodetects disks).
