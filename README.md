# Void Linux X220 Tablet Setup

Idempotent provisioning + dotfiles for a ThinkPad X220 Tablet running
**Void Linux** with **Sway** (Wayland) and/or **KDE Plasma 6** as the
desktop environment. All scripts are modular: pick what you want, skip
what you don't.

Themed to Breeze Dark for visual consistency across both DEs.

For deeper detail on architecture, conventions, and per-script
responsibilities, see [CLAUDE.md](./CLAUDE.md).

---

## Quick start

All scripts support `-d/--dry-run` (preview without changes) and
`-h/--help`. Run them from the repo root.

### Step 0 — Fresh install only

If you are installing on an empty disk from the Void live ISO:

```bash
./setup-disk.sh /dev/sda   # interactive cfdisk + mkfs + mount
```

Then run `void-installer`, pointing it at the mounts already created
(do **not** re-format). After installation, reboot into the new system
before continuing.

> Skip Step 0 if you are running these scripts on an existing Void install.

---

### Path A — Sway only

```bash
./setup-base.sh         # common system foundation (NM, SDDM, audio, BT, fonts, Qt, shell, CLI)
./setup-sway.sh         # Sway compositor + waybar/fuzzel/mako/foot/screenshots
./setup-dotfiles.sh     # user configs (sway, waybar, alacritty, zsh, etc.)
```

Reboot and pick **Sway** from the SDDM session menu.

---

### Path B — Plasma only

```bash
./setup-base.sh         # common system foundation
./setup-plasma.sh       # Plasma 6 desktop + KDE applets + extras
```

Reboot and pick **Plasma (Wayland)** from the SDDM session menu. See
[Post-install manual steps](#post-install-manual-steps) for the GUI
polish (Apply Plasma Settings, bezel button mapping, Maliit, etc.).

> `setup-dotfiles.sh` is Sway-focused; skip it for a Plasma-only setup.

---

### Path C — Both side-by-side

Install both DEs, pick which one to use from the SDDM menu each login.

```bash
./setup-base.sh         # common foundation
./setup-sway.sh         # Sway stack
./setup-plasma.sh       # Plasma stack
./setup-dotfiles.sh     # Sway configs (does not affect Plasma)
```

---

## Optional add-ons

Run any of these in any order, **after** the path above. Each is
self-contained and idempotent.

| Script | What it does | Flags |
|---|---|---|
| `setup-zram.sh` | zram compressed swap (zstd, 50%, prio 32767) + `vm.swappiness=100` | `--with-swapfile` also creates `/swapfile` (prio=10) as OOM backstop |
| `setup-fingerprint.sh` | fprintd + libfprint, probes UPEK reader (`147e:2016`), reports enrollment | — |
| `setup-virtualkb.sh` | Maliit on-screen keyboard for Plasma sessions | `--enable-sddm` also wires the SDDM greeter vkbd |
| `setup-voidsplash.sh` | Framebuffer boot splash via runit (no Plymouth, no initramfs changes) | `--grub-quiet` also adds `console=tty2` to GRUB so kernel logs render off-splash |

For Sway, the on-screen keyboard is `wvkbd` — already installed by
`setup-sway.sh` and bound to `Mod+Shift+T` in the dotfiles. Maliit is
Plasma-specific.

---

## Preview before applying

Every setup script supports `--dry-run`:

```bash
./setup-base.sh --dry-run
./setup-sway.sh --dry-run
./setup-plasma.sh --dry-run
# ... etc.
```

Dry-run logs every action that would be taken (package installs, service
symlinks, file writes, env-var appends) without touching the system.

---

## Post-install manual steps

Some things can't (or shouldn't) be scripted. This section collects the
follow-up actions documented in the install log, organized by what
triggers them.

### After `setup-plasma.sh` (GUI-only steps)

- **Apply Plasma Settings to SDDM** — System Settings → Startup and
  Shutdown → Login Screen (SDDM) → select **Breeze** → click
  **"Apply Plasma Settings"**. This copies Plasma's wallpaper, color
  scheme, and font into SDDM. Without it the Breeze theme looks bare.
- **Map the bezel rotation button** — System Settings → Shortcuts →
  Custom Shortcuts → New → Global Shortcut → Command/URL. Trigger:
  press the bezel rotation button (captures `XF86TaskPane`). Action:
  `~/.local/bin/rotate_screen_twm.sh`. (In Sway this binding
  is already in `dotfiles/sway/config` — no GUI step needed.)
- ⚠️ **NEVER set `DisplayServer=wayland`** in any
  `/etc/sddm.conf.d/*.conf` — this has fully hung the X220 in the past
  (no TTY response either). SDDM's greeter MUST stay in X; the Wayland
  session is picked from the menu at login.

### After `setup-fingerprint.sh`

- **Enroll a fingerprint** — `fprintd-enroll`. Swipe slow and even,
  top-to-bottom, finger flat and centered, covering the whole strip.
  Fast swipes give `enroll-swipe-too-short`. Verify with
  `fprintd-verify`. UPEK matching is somewhat inconsistent (typical of
  the chip); re-enroll with uniform swipes if it misses too often.
- **(Optional) PAM integration** — edit `/etc/pam.d/sudo` (or any other
  PAM stack you want fingerprint auth on) and add as the FIRST auth
  line:
  ```
  auth sufficient pam_fprintd.so
  ```
  ⚠️ Always use `sufficient`, **never** `required` alone — CVE-2024-37408
  covers vulnerabilities in solo-fingerprint setups. Keep password as
  fallback.

### After `setup-virtualkb.sh` (Plasma sessions)

- **Enable Maliit** — System Settings → Input Devices → Virtual
  Keyboard → **Maliit**. The pane only appears under Wayland (not X11).
  Touching a text field will pop the keyboard.
- For Sway, the on-screen keyboard is `wvkbd` and is already bound to
  `Mod+Shift+T` by the dotfiles — no extra step.

### After `setup-zram.sh` — decide on swapfile backstop

zram alone is fine for light workloads. With a browser open, the X220
can OOM when zram fills. You have two options (bitácora §13):

- **Option A (default)** — just zram. Simpler, no disk writes. Accept
  the OOM risk.
- **Option B (recommended for browser use)** — re-run
  `./setup-zram.sh --with-swapfile`. Creates `/swapfile` (8 GB,
  priority 10), which only takes effect when zram is fully exhausted.
  The `pri=10` is well below zram's 32767 so zram still fills first.

Verify either with:
```bash
zramctl                # should show /dev/zram0 with zstd
swapon --show          # zram + (optional) /swapfile with priorities
free -h
```

### Hardware exploration (X220 Tablet)

- **Identify the other two bezel buttons** — only the rotation button
  (`XF86TaskPane`) is currently mapped. To identify the rest:
  ```bash
  wev               # run, press each bezel button, read the keysym
  sudo evtest       # alternative if wev does not capture them
  ```
  Once identified, add bindings in `dotfiles/sway/config` next to the
  existing `bindsym XF86TaskPane` line.

### Verification quick-reference

```bash
# Audio
pactl info                                                # should show "PulseAudio (on PipeWire ...)"
pw-play /usr/share/sounds/alsa/Front_Center.wav           # speaker test

# Bluetooth
sudo sv status bluetoothd                                 # should say run:
bluetoothctl list                                         # should list Broadcom adapter

# zram
zramctl ; swapon --show ; free -h

# Locale / timezone (waybar clock)
date                                                      # should show local time
locale                                                    # should show LANG=en_US.UTF-8 if set
```

### Hardware notes (X220 Tablet quirks)

These are context for the design decisions — nothing to do, just worth
knowing:

- **GPU**: Intel Sandy Bridge HD 3000 → driver `mesa` + kernel module
  `i915`. `mesa-dri` is mandatory; without it SDDM is a black screen.
- **WiFi**: Intel iwlwifi. If it dies after a reboot, install
  `linux-firmware-network`.
- **Auto-rotation is impossible** — the accelerometer is HDAPS (via
  `thinkpad_acpi`), NOT exposed as IIO under `/sys/bus/iio/devices/`.
  `iio-sensor-proxy` has no source to read, so rotation is button-only.
- **UPEK fingerprint reader**: USB ID `147e:2016`. If `lsusb` does not
  list it, check BIOS → Security → Fingerprint.
- **Display panel**: `LVDS-1` (not `eDP-1`), 1280×800, 16:10.
  Voidsplash frames must match this aspect ratio or fbv shows black
  bars.
- **Stylus**: Wacom ISDv4 E6 Pen / Finger. Native via libinput on
  Wayland — no Xorg config files needed.

---

## Repository layout

```
setup-disk.sh              pre-install partitioning (live ISO)
setup-base.sh              common system foundation
setup-sway.sh              Sway compositor + helpers
setup-plasma.sh            KDE Plasma 6 stack
setup-dotfiles.sh          user-level dotfiles installer
setup-zram.sh              zram + sysctl swap setup
setup-fingerprint.sh       UPEK fingerprint setup
setup-virtualkb.sh         Maliit virtual keyboard (Plasma)
setup-voidsplash.sh        runit boot splash
dotfiles/                  payload copied into ~/.config + ~/.local/bin
images/                    wallpapers copied into ~/Pictures
CLAUDE.md                  internal guidance for AI coding assistants
```
