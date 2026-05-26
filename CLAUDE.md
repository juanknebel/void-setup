# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Provisioning + dotfiles for a **ThinkPad X220 Tablet running Void Linux + Sway (Wayland)**, themed to Breeze Dark for visual consistency with KDE Plasma 6 / Konsole. Not a generic dotfiles repo — many design decisions are X220-specific (see "Hardware-specific gotchas" below).

## Common commands

Both setup scripts are idempotent and support `--dry-run` for previews. There are **no build/lint/test commands** — this is a config repo.

```bash
./setup-system.sh --dry-run    # preview system changes
./setup-system.sh              # apply (xbps packages, runit services, zram, SDDM, env vars)
./setup-dotfiles.sh --dry-run  # preview user-config changes
./setup-dotfiles.sh            # apply (copies dotfiles/ + images/ into $HOME)
```

## Architecture

Two-script split:

- **`setup-system.sh`** = system-level (needs sudo). Installs xbps packages, sets up runit service symlinks, writes `/etc/sv/zramen/conf` via heredoc, configures SDDM theme, links PipeWire system configs, appends `QT_QPA_PLATFORMTHEME=qt6ct` to `/etc/environment`.
- **`setup-dotfiles.sh`** = user-level (no sudo). Copies payload from `dotfiles/` and `images/` into `~/.config/`, `~/.local/bin/`, `~/Pictures/`.

The dotfiles installer uses a **mirror-of-destination layout**: `dotfiles/sway/config` → `~/.config/sway/config`, `dotfiles/local/bin/powermenu.sh` → `~/.local/bin/powermenu.sh`. The `install_file` helper takes absolute src paths; callers build them from `$DOTFILES_DIR` or `$IMAGES_DIR`. Backups of overwritten files go to `<path>.bak.<timestamp>`.

When extending the installer with a new payload source (other than `dotfiles/` and `images/`), define a new `*_DIR` variable at the top and pass `"$NEW_DIR/relpath"` to `install_file` — don't duplicate the helper.

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

Theming relies on `QT_QPA_PLATFORMTHEME=qt6ct` exported from `/etc/environment` (set by section 12 of setup-system.sh), plus `qt6ct`, `kvantum`, `breeze-icons` packages. Without this, Qt apps render without toolbar icons and default Fusion palette. The user runs `qt6ct` once to pick style + icon theme — that's a preference, not script-managed.

## Hardware-specific gotchas (X220 Tablet)

These affect script defaults; flagging the non-obvious ones:

- **mesa-dri** is mandatory; without it SDDM is a black screen on the Intel HD 3000 (Sandy Bridge).
- **elogind** is mandatory for Wayland; without it Sway/Plasma can't create the Wayland socket.
- **libspa-bluetooth** is needed for BT audio (without it pairing works but no sound).
- **HDAPS accelerometer is NOT exposed as IIO** — `iio-sensor-proxy` doesn't work, so auto-rotation is impossible. Rotation is manual-only via bezel button + script.
- **UPEK fingerprint reader (147e:2016)** works with fprintd on this unit. PAM integration is intentionally NOT enabled by this repo.
- **Do NOT set `DisplayServer=wayland` in SDDM** — it locks the X220 entirely (the bitácora has the war story).
