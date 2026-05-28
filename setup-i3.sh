#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# Installs i3 and the user-space helpers wired into dotfiles/i3/config
# (polybar, dunst, picom, rofi, flameshot, etc.).
# Assumes setup-base.sh has already run (provides X11 prereqs,
# fonts, audio, libinput, etc.).

# --- Configuration ---
DRY_RUN=false
PACKAGES=(
    # Window manager
    i3
    # Status bar — highly configurable, analogous to waybar
    polybar
    # Compositor — provides shadows and transparency for X11 sessions.
    # Uses the xrender backend by default (safer on Intel GMA X3100).
    picom
    # Notification daemon (Breeze Dark themed via dunstrc)
    dunst
    # App launcher (replaces fuzzel)
    rofi
    # Screen locker
    i3lock
    # Screenshots + annotation GUI (replaces grim + satty)
    flameshot
    # Clipboard (X11 — replaces wl-clipboard)
    xclip
    # Wallpaper setter (replaces swaybg)
    feh
    # Display management CLI and GUI
    xrandr arandr
    # Input device control (used by rotate_screen_x11.sh for Wacom remapping)
    xinput
    # Idle auto-lock (replaces swayidle)
    xautolock
    # Hardware controls + TUIs
    brightnessctl pulsemixer bluetui
    # File manager (same as base — listed for clarity; no-op if already installed)
    pcmanfm-qt
    # Key/button event inspector (replaces wev)
    xev
    # X11 automation (useful for scripting window management)
    xdotool
)

# Prerequisites assumed already installed by setup-base.sh.
REQUIRED_PREREQS=(mesa-dri xorg-minimal sddm dbus polkit pipewire wireplumber libinput nerd-fonts-ttf)

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
    echo "Installs i3 and its helper utilities. Run setup-base.sh first."
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
    log_info "=== INITIALIZING i3 WINDOW MANAGER STACK ==="
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# --- 1. Prerequisite Validation ---
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
    log_err "Run ./setup-base.sh first to install the base stack."
    exit 1
fi

# --- 2. i3 Package Installation ---
log_info "Checking i3 packages against xbps..."
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
    log_success "All i3 packages are satisfied."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Packages slated for installation: ${MISSING_PACKAGES[*]}"
    else
        log_info "Installing missing i3 packages: ${MISSING_PACKAGES[*]}"
        sudo xbps-install -S "${MISSING_PACKAGES[@]}"
    fi
fi

log_success "=== i3 WINDOW MANAGER STACK COMPLETE ==="
if [ "$DRY_RUN" = false ]; then
    log_info "Run ./setup-dotfiles.sh next to copy the i3/polybar/dunst configs into your HOME."
    log_info "For X61 Tablet hardware (Wacom, thinkfan, TLP): run ./setup-x61.sh."
    log_info "Then reboot and pick the 'i3' session from the SDDM menu."
fi
