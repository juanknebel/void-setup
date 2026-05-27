#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Configuration ---
DRY_RUN=false
PACKAGES=(
    # Core Plasma desktop + window manager (KWin ships inside plasma-desktop).
    plasma-desktop
    # Plasma applets / system integration
    plasma-nm           # NetworkManager applet
    plasma-pa           # Volume control applet
    kscreen             # Display + rotation management
    powerdevil          # Power management (battery, lid close, suspend)
    bluedevil           # Bluetooth GUI integration
    # SDDM theme configuration UI
    sddm-kcm
    # Basic KDE apps usually missing from a minimal install
    dolphin             # File manager
    kinfocenter         # Hardware / driver info panel
    kate                # Advanced text editor
    # Plasma extras
    plasma-disks                # SMART monitoring widget
    plasma-keyboard             # KWin native virtual keyboard
    plasma-wayland-protocols    # Extra Wayland protocols for KDE
    kdeplasma-addons            # Widget collection (calc, weather, notes, ...)
    # Plasma 6 meta-packages. Naming is legacy ("kde5") in Void but installs
    # Plasma 6. Pulled in to register the default multimedia shortcut scheme
    # so XF86Audio* keys work with native OSD.
    kde5
    kde5-baseapps
)

# Prerequisites assumed already installed by setup-system.sh:
#   elogind, xorg-minimal, mesa-dri, xorg-server-xwayland, sddm,
#   pipewire, wireplumber, dbus, polkit.
REQUIRED_PREREQS=(elogind mesa-dri xorg-server-xwayland sddm dbus polkit)

# Colors for output formatting
NC='\033[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${ORANGE}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Installs the KDE Plasma desktop stack alongside Sway on the X220."
    echo "Run setup-system.sh FIRST — this script assumes its prerequisites"
    echo "(elogind, mesa-dri, Xwayland, sddm, pipewire, dbus, polkit) are present."
    echo ""
    echo "Options:"
    echo "  -d, --dry-run    Validate packages without installing."
    echo "  -h, --help       Show this help message."
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run) DRY_RUN=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) log_err "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    log_warn "=== RUNNING IN DRY-RUN MODE (NO CHANGES WILL BE MADE) ==="
else
    log_info "=== INITIALIZING PLASMA DESKTOP STACK ==="
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# --- 1. Prerequisite Validation ---
# Plasma Wayland needs the Wayland session stack from setup-system.sh.
# Without elogind specifically, KWin Wayland cannot create its socket
# ("Could not create wayland socket" in wayland-session.log).
log_info "Validating system prerequisites..."
MISSING_PREREQS=()
for pkg in "${REQUIRED_PREREQS[@]}"; do
    if ! xbps-query "$pkg" > /dev/null 2>&1; then
        MISSING_PREREQS+=("$pkg")
    fi
done

if [ ${#MISSING_PREREQS[@]} -eq 0 ]; then
    log_success "All prerequisites are present."
else
    log_err "Missing prerequisites: ${MISSING_PREREQS[*]}"
    log_err "Run ./setup-system.sh first to install the base stack."
    exit 1
fi

# --- 2. Plasma Package Installation ---
log_info "Checking Plasma packages against xbps..."
MISSING_PACKAGES=()
for pkg in "${PACKAGES[@]}"; do
    if xbps-query "$pkg" > /dev/null 2>&1; then
        log_success "Package '$pkg' is already installed. Skipping."
    else
        if xbps-query -R "$pkg" > /dev/null 2>&1; then
            log_warn "Package '$pkg' is missing but available in repositories."
            MISSING_PACKAGES+=("$pkg")
        else
            log_err "Package '$pkg' was not found in active Void repositories!"
        fi
    fi
done

if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
    log_success "All Plasma packages are satisfied."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Packages slated for installation: ${MISSING_PACKAGES[*]}"
    else
        log_info "Installing missing Plasma packages: ${MISSING_PACKAGES[*]}"
        sudo xbps-install -S "${MISSING_PACKAGES[@]}"
    fi
fi

# --- 3. Plasma Qt platform theme drop-in ---
# setup-base.sh sets QT_QPA_PLATFORMTHEME=qt6ct globally in /etc/environment
# (correct for Sway), but under Plasma that hijacks the `kde` platform theme
# and Qt apps stop responding to Plasma System Settings color/icon changes.
# Plasma sources env/*.sh after PAM, so this drop-in overrides the global
# default for Plasma sessions only — Sway is untouched.
QT_DROPIN_DIR="/etc/xdg/plasma-workspace/env"
QT_DROPIN_FILE="$QT_DROPIN_DIR/qt-platform-theme.sh"
QT_DROPIN_CONTENT='export QT_QPA_PLATFORMTHEME=kde'

if [ -f "$QT_DROPIN_FILE" ] && grep -qxF "$QT_DROPIN_CONTENT" "$QT_DROPIN_FILE"; then
    log_success "Plasma Qt platform theme drop-in already in place."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Would write $QT_DROPIN_FILE with: $QT_DROPIN_CONTENT"
    else
        log_info "Writing Plasma Qt platform theme drop-in to $QT_DROPIN_FILE"
        sudo install -d "$QT_DROPIN_DIR"
        echo "$QT_DROPIN_CONTENT" | sudo tee "$QT_DROPIN_FILE" > /dev/null
        sudo chmod +x "$QT_DROPIN_FILE"
        log_success "Drop-in installed."
    fi
fi

# --- 4. Plasma screen rotation helper ---
# Companion to dotfiles/local/bin/rotate_screen_twm.sh (the Sway version).
# Installed here rather than via setup-dotfiles.sh because that installer is
# Sway-focused; this is the Plasma equivalent that drives kscreen-doctor.
# Bind it to a custom shortcut in System Settings → Shortcuts (the bezel
# rotation button on the X220 emits XF86TaskPane, same as under Sway).
ROTATE_SRC="$SCRIPT_DIR/dotfiles/local/bin/rotate_screen_kde.sh"
ROTATE_DST="$HOME/.local/bin/rotate_screen_kde.sh"

if [ ! -f "$ROTATE_SRC" ]; then
    log_warn "Source $ROTATE_SRC not found — skipping rotate_screen_kde install."
elif [ -f "$ROTATE_DST" ] && cmp -s "$ROTATE_SRC" "$ROTATE_DST"; then
    log_success "rotate_screen_kde.sh already up to date at $ROTATE_DST."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Would install $ROTATE_SRC -> $ROTATE_DST"
    else
        mkdir -p "$(dirname "$ROTATE_DST")"
        if [ -f "$ROTATE_DST" ]; then
            ts=$(date +%Y%m%d%H%M%S)
            cp -a "$ROTATE_DST" "$ROTATE_DST.bak.$ts"
            log_info "Backed up existing $ROTATE_DST to .bak.$ts"
        fi
        install -m 0755 "$ROTATE_SRC" "$ROTATE_DST"
        log_success "Installed $ROTATE_DST"
    fi
fi

log_success "=== PLASMA DESKTOP STACK COMPLETE ==="
if [ "$DRY_RUN" = false ]; then
    log_info "Reboot and pick 'Plasma (Wayland)' from the SDDM session menu."
    log_info ""
    log_info "After first login, polish the SDDM look:"
    log_info "  System Settings → Startup and Shutdown → Login Screen (SDDM)"
    log_info "    → select Breeze → click 'Apply Plasma Settings'."
    log_info "  This copies the Plasma wallpaper / color scheme / font into SDDM."
    log_info ""
    log_info "To bind the screen rotation helper:"
    log_info "  System Settings → Shortcuts → Custom Shortcuts → Edit → New → Global Shortcut → Command/URL"
    log_info "    Trigger: XF86TaskPane (X220 bezel button) or any keys you prefer"
    log_info "    Action:  ~/.local/bin/rotate_screen_kde.sh"
    log_info ""
    log_info "DO NOT set DisplayServer=wayland in any /etc/sddm.conf.d/*.conf —"
    log_info "the X220 has hung hard on that setting (greeter stays in X, sessions go Wayland)."
fi
