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

Reboot and pick **Plasma (Wayland)** from the SDDM session menu. After
first login, polish SDDM: System Settings → Startup → Login Screen →
select Breeze → **Apply Plasma Settings**.

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
