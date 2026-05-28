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
- **`setup-base.sh`** = system foundation (needs sudo). Installs packages for NM/SDDM/audio/BT/input/fonts/shell/CLI/Qt+GTK-theming, sets up runit service symlinks, configures SDDM theme to Breeze, links PipeWire system configs + user autostart, appends `QT_QPA_PLATFORMTHEME=qt6ct` to `/etc/environment`.
- **`setup-i3.sh`** = i3 compositor additions. Validates base prerequisites first. Adds the X11 WM stack: i3, polybar, picom, dunst, rofi, flameshot, xclip, feh, xrandr, xinput, xautolock, brightnessctl, pulsemixer, bluetui.
- **`setup-dotfiles.sh`** = user-level (no sudo). Copies payload from `dotfiles/` and `images/` into `~/.config/`, `~/.local/bin/`, `~/Pictures/`. Uses `install_file` with timestamp backups.
- **`setup-x61.sh`** = optional X61 Tablet hardware. Installs xf86-input-wacom, libwacom, tlp, thinkfan, hdapsd, acpi_call. Writes `/etc/X11/xorg.conf.d/70-wacom.conf`, `/etc/thinkfan.conf`, `/etc/tlp.conf`, `/etc/modules-load.d/acpi_call.conf`. Enables runit services: tlp, thinkfan, hdapsd.
- **`setup-zram.sh`** = optional. Same as main branch — hardware-agnostic.
- **`setup-fingerprint.sh`** = optional. Same as main branch — verify your USB ID before relying on it.

All scripts follow the same shape: `set -euo pipefail`, color-coded `log_*` helpers, `--dry-run`/`--help` flags, idempotent xbps package check loop, sudo keep-alive in non-dry-run mode.

## Conventions worth knowing

### Language

**All comments, documentation, commit messages, and any text inside files in this repo MUST be in English**, regardless of file type (configs, shell scripts, dotfiles, `.gitignore`, markdown, etc.). The user's chat language is Spanish but the codebase is English-only. When editing existing files, translate any Spanish text encountered to English in the same pass.

### i3 config

- `;` has no special meaning in i3 config. Multi-command exec uses `sh -c '...'`.
- The `sleep 0.3` in `exec_always` guards avoid a cold-boot race where i3 fires helpers before the X session is fully initialized.
- Panel output is **`LVDS1`** on the X61 (X11/xrandr convention — not `LVDS-1` which is a Wayland/KMS convention).
- Rotation button on the bezel emits **`XF86RotateWindows`** (different from X220's `XF86TaskPane`). Also bound to `Mod+Shift+R` as keyboard equivalent.
- Multimedia/lock bindings use `wpctl` (from wireplumber) and `brightnessctl`.
- Floating TUI popups use `alacritty --class <name>,Alacritty` + `for_window [instance="<name>"]` in i3 config.

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
- **Wacom ISD300 digitizer** — X11 driver is `xf86-input-wacom`. The exact xinput device name varies by firmware. Verify with `xinput list | grep -i wacom` and set `WACOM_DEVICE` env var if it differs from `Wacom ISD`.
- **LVDS1** is the X11/xrandr output name (not `LVDS-1`). Hardcoded in `rotate_screen_x11.sh`.
- **XF86RotateWindows** is the rotation button keysym on the X61 (not `XF86TaskPane` which is X220-specific). Verify with `xev` if the button doesn't respond.
- **No IIO accelerometer** — rotation is manual-only via bezel button + script.
- **acpi_call kernel module** for battery charge thresholds — written to `/etc/modules-load.d/acpi_call.conf` by `setup-x61.sh`, loads on next reboot.
- **thinkfan** reads `/proc/acpi/ibm/thermal` for temperatures. The conservative defaults in `setup-x61.sh` may need tuning for your specific unit.
- **HDAPS accelerometer** is exposed under `/sys/devices/platform/thinkpad_acpi` and used by `hdapsd` for HDD head parking on shock. Not related to screen rotation.
