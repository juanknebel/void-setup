# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Provisioning + dotfiles for a **ThinkPad X220 Tablet running Void Linux + Sway (Wayland)**, themed to Breeze Dark for visual consistency with KDE Plasma 6 / Konsole. Not a generic dotfiles repo — many design decisions are X220-specific (see "Hardware-specific gotchas" below).

## Common commands

All setup scripts are idempotent and support `--dry-run` for previews. There are **no build/lint/test commands** — this is a config repo.

The scripts are deliberately modular so you can build either a Sway box, a Plasma box, or both — pick which to run, none are mandatory beyond `setup-base.sh`.

```bash
# Pre-install (run only on a fresh disk, from the live ISO; needs root)
./setup-disk.sh /dev/sda          # interactive cfdisk + automated mkfs/mount

# After void-installer + first boot
./setup-base.sh                   # common base (NM, SDDM, audio, BT, fonts, Qt theming, shell, CLI)

# Pick your desktop(s) — both can coexist
./setup-sway.sh                   # sway compositor + helpers (waybar, fuzzel, mako, foot, screenshots)
./setup-plasma.sh                 # KDE Plasma desktop + applets + extras

# User configs (copies dotfiles/ + images/ into $HOME; sway-focused)
./setup-dotfiles.sh

# Optional add-ons
./setup-zram.sh                   # zram swap (zstd, 50%, prio 32767) + swappiness=100
                                  #   --with-swapfile also creates /swapfile (pri=10) as OOM backstop
./setup-fingerprint.sh            # fprintd + libfprint, probes UPEK reader (147e:2016)
./setup-virtualkb.sh              # Maliit for Plasma; --enable-sddm also wires greeter vkbd
./setup-voidsplash.sh             # framebuffer boot splash via runit
                                  #   --grub-quiet also adds console=tty2 to GRUB cmdline
```

Every script supports `-d/--dry-run` and `-h/--help`.

## Architecture

The repo is a layered set of standalone scripts. Each script is independently runnable and idempotent. The layers form a dependency chain:

```
setup-disk.sh         (pre-install, in live ISO)
       ↓
   [void-installer, reboot]
       ↓
setup-base.sh         (common system: NM/SDDM/audio/BT/fonts/Qt/shell/CLI)
       ↓                                   ↓
setup-sway.sh                     setup-plasma.sh   (pick one or both)
       ↓                                   ↓
setup-dotfiles.sh                 [Plasma GUI config]
       ↓
[optional add-ons: setup-zram.sh, setup-fingerprint.sh,
                   setup-virtualkb.sh, setup-voidsplash.sh]
```

Per-script responsibilities:

- **`setup-disk.sh`** = pre-install only. Takes a target device, runs cfdisk interactively, then automates mkfs.vfat (ESP) + mkfs.ext4 (root) + mount under `/mnt`. Has strict guard rails: refuses if any partition on the target is mounted, requires root (no sudo in live ISO), requires explicit `yes` confirmation before mkfs.
- **`setup-base.sh`** = system foundation shared by both DEs (needs sudo). Installs xbps packages for NM/SDDM/audio/BT/input/fonts/shell/CLI/Qt-theming, sets up runit service symlinks, configures SDDM theme to Breeze, links PipeWire system configs + user autostart, appends `QT_QPA_PLATFORMTHEME=qt6ct` to `/etc/environment`, cleans up stale dhcpcd. Other DE/optional scripts validate its prerequisites and bail with a clear error if missing.
- **`setup-sway.sh`** / **`setup-plasma.sh`** = compositor/DE additions. Both validate base prerequisites first. Sway adds the wlroots stack + helpers (waybar, fuzzel, mako, screenshots tooling). Plasma adds the Plasma 6 stack + KDE apps. Both can be installed side-by-side and selected from the SDDM session menu.
- **`setup-dotfiles.sh`** = user-level (no sudo). Copies payload from `dotfiles/` and `images/` into `~/.config/`, `~/.local/bin/`, `~/Pictures/`. Sway-focused (the dotfiles assume Sway; Plasma users configure via GUI). Uses a mirror-of-destination layout where `install_file` takes absolute src paths from `$DOTFILES_DIR` or `$IMAGES_DIR`; backups go to `<path>.bak.<timestamp>`.
- **`setup-zram.sh`** = optional. Installs zramen, writes `/etc/sv/zramen/conf` via heredoc (zstd / 50% / priority 32767), links the runit service, writes `vm.swappiness=100`. `--with-swapfile` additionally creates `/swapfile` at priority 10 as an anti-OOM backstop (zram fills first).
- **`setup-fingerprint.sh`** = optional UPEK setup. Installs fprintd/libfprint, probes USB ID `147e:2016`, reports enrollment status. PAM integration intentionally NOT scripted — manual opt-in with mandatory `sufficient` semantics (CVE-2024-37408).
- **`setup-virtualkb.sh`** = optional Maliit for Plasma sessions. `--enable-sddm` flag also writes `/etc/sddm.conf.d/10-virtualkbd.conf` for greeter vkbd (kept opt-in because SDDM tweaks have hung the X220 in the past).
- **`setup-voidsplash.sh`** = optional boot splash. Clones jaylesworth/voidsplash, installs binary to `/bin/voidsplash`, creates runit service, copies bundled sample frames to `/etc/voidsplash/`. `--grub-quiet` flag also appends `console=tty2` to `GRUB_CMDLINE_LINUX_DEFAULT` so kernel logs don't paint over the splash.

All scripts follow the same shape: `set -euo pipefail`, color-coded `log_*` helpers, `--dry-run`/`--help` flags, idempotent xbps package check loop, sudo keep-alive in non-dry-run mode. There is **intentional duplication** of these helpers across scripts (no shared library) — keeps each script standalone runnable.

When extending the dotfiles installer with a new payload source (other than `dotfiles/` and `images/`), define a new `*_DIR` variable at the top and pass `"$NEW_DIR/relpath"` to `install_file` — don't duplicate the helper.

## Conventions worth knowing

### Language

**All comments, documentation, commit messages, and any text inside files in this repo MUST be in English**, regardless of file type (configs, shell scripts, dotfiles, `.gitignore`, markdown, etc.). The user's chat language is Spanish but the codebase is English-only. When editing existing files, translate any Spanish text encountered to English in the same pass.

### Sway config

- `;` is a **sway-config-level separator**, not shell. Multi-command exec must be wrapped: `exec_always sh -c 'pkill -x waybar; sleep 0.3; waybar'`. The `sleep 0.3` avoids a cold-boot race where helpers start before the Wayland socket is ready.
- Panel output is **`LVDS-1`** on the X220 (not `eDP-1`). `rotate_screen_twm.sh` hardcodes this.
- Rotation button on the bezel emits **`XF86TaskPane`** (not the "natural" `XF86RotateWindows`). Also bound to `Mod+Shift+R` as keyboard equivalent.
- Multimedia/lock bindings use `wpctl` (from wireplumber) and `brightnessctl`.

### Shells

- **System shell stays `bash`**. `chsh` is intentionally NOT performed.
- alacritty and foot launch `zsh -l` via their own config — terminals open zsh, TTYs/scripts/SSH stay on bash.
- Scripts with `#!/bin/sh` (powermenu.sh, rotate_screen_twm.sh) run under **dash** on Void. Use `printf`, not `echo -e` (dash prints `-e` literally as the first arg).

### Color palette (strict Breeze Dark / Plasma 6)

| Role | Hex | Where |
|---|---|---|
| Plasma View bg | `#232629` | sway client bg, waybar, mako, fuzzel, swaylock |
| Plasma Window bg | `#31363b` | swaylock ring inside-color, fuzzel selection |
| Konsole bg | `#232627` | alacritty + foot only |
| Accent / selection | `#3daee9` | focus border, active workspace, ring |
| Muted fg | `#7f8c8d` | inactive text |
| Border alt | `#4d4d4d` | inactive borders, powerline separator |
| Urgent | `#ed1515` | client.urgent, battery critical |

Don't introduce non-Breeze colors (e.g. `#1d1f21`, which was an earlier mistake). The full ANSI palette in foot/alacritty mirrors Konsole's Breeze Dark.

### Qt apps

Theming relies on `QT_QPA_PLATFORMTHEME=qt6ct` exported from `/etc/environment` (set by `setup-base.sh`), plus `qt6ct`, `kvantum`, `breeze-icons` packages. Without this, Qt apps render without toolbar icons and default Fusion palette. The user runs `qt6ct` once to pick style + icon theme — that's a preference, not script-managed.

## Hardware-specific gotchas (X220 Tablet)

These affect script defaults; flagging the non-obvious ones:

- **mesa-dri** is mandatory; without it SDDM is a black screen on the Intel HD 3000 (Sandy Bridge).
- **elogind** is mandatory for Wayland; without it Sway/Plasma can't create the Wayland socket.
- **libspa-bluetooth** is needed for BT audio (without it pairing works but no sound).
- **HDAPS accelerometer is NOT exposed as IIO** — `iio-sensor-proxy` doesn't work, so auto-rotation is impossible. Rotation is manual-only via bezel button + script.
- **UPEK fingerprint reader (147e:2016)** works with fprintd on this unit. PAM integration is intentionally NOT enabled by this repo.
- **Do NOT set `DisplayServer=wayland` in SDDM** — it locks the X220 entirely (the bitácora has the war story).
