#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# Installs the Sway compositor and the user-space helpers wired into
# dotfiles/sway/config (waybar, mako, swaylock, fuzzel, foot, etc.).
# Assumes setup-base.sh has already run (provides Wayland prereqs,
# fonts, audio, libinput, etc.).

# --- Configuration ---
DRY_RUN=false
PACKAGES=(
    # Sway compositor + window utilities
    sway swaybg swaylock swayidle Waybar fuzzel mako wlr-randr
    # Screenshots + clipboard (Wayland-native stack)
    # grim     = capture · slurp = region select · satty = annotate
    # wl-clipboard = wl-copy/wl-paste · cliphist = persistent history,
    # surfaced via fuzzel (bound to Mod+Shift+v in dotfiles/sway/config).
    grim slurp satty wl-clipboard cliphist
    # XDG desktop portals — needed for screenshare in Firefox/Chromium,
    # file pickers under Flatpaks, and any "Open With" dialog from a
    # Wayland-only app. The -wlr backend is the wlroots-based one Sway
    # exposes; -gtk provides the file-chooser implementation.
    xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    # Terminal + virtual keyboard for tablet mode
    # foot is the secondary terminal used by waybar TUI popups (nmtui/bluetui/pulsemixer);
    # wvkbd is the on-screen keyboard bound to Mod+Shift+T.
    foot wvkbd
    # Hardware controls — TUIs invoked from waybar + CLI for backlight
    pulsemixer bluetui brightnessctl
    # ACPI event daemon — handles lid-close and power-button events even
    # when no Wayland session is running (e.g. SDDM greeter or a TTY).
    # Configured below to suspend on lid close.
    acpid
    # Tablet bezel button identification under Wayland
    wev evtest
)

# Prerequisites assumed already installed by setup-base.sh.
REQUIRED_PREREQS=(elogind mesa-dri xorg-server-xwayland sddm dbus polkit pipewire wireplumber libinput libwacom nerd-fonts-ttf)

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
    echo "Installs Sway and its helper utilities. Run setup-base.sh first."
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
    log_info "=== INITIALIZING SWAY COMPOSITOR STACK ==="
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

# --- 2. Sway Package Installation ---
log_info "Checking Sway packages against xbps..."
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
    log_success "All Sway packages are satisfied."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Packages slated for installation: ${MISSING_PACKAGES[*]}"
    else
        log_info "Installing missing Sway packages: ${MISSING_PACKAGES[*]}"
        sudo xbps-install -S "${MISSING_PACKAGES[@]}"
    fi
fi

# --- 3. ACPI events: lid close → suspend ---
# Supervise acpid under runit (same symlink pattern setup-base.sh uses)
# and drop a single event handler that suspends on lid close. We use
# `loginctl suspend` because elogind (installed by setup-base.sh) is the
# session manager — `zzz` would also work but bypasses session locking.
log_info "Configuring acpid lid handler..."
ACPID_SV_TARGET="/etc/sv/acpid"
ACPID_SV_LINK="/var/service/acpid"

if [ ! -d "$ACPID_SV_TARGET" ]; then
    log_err "Runit source service directory '$ACPID_SV_TARGET' does not exist (is acpid installed?)."
elif [ -L "$ACPID_SV_LINK" ]; then
    ACTUAL="$(readlink "$ACPID_SV_LINK")"
    if [ "${ACTUAL%/}" = "$ACPID_SV_TARGET" ]; then
        log_success "acpid service link active: $ACPID_SV_LINK -> $ACPID_SV_TARGET"
    else
        log_err "Symlink conflict: $ACPID_SV_LINK -> $ACTUAL (expected $ACPID_SV_TARGET)."
    fi
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Will link $ACPID_SV_LINK -> $ACPID_SV_TARGET"
    else
        log_info "Activating runit management link for: acpid"
        sudo ln -sf "$ACPID_SV_TARGET" "$ACPID_SV_LINK"
    fi
fi

ACPID_EVENTS_DIR="/etc/acpi/events"
ACPID_LID_FILE="$ACPID_EVENTS_DIR/lid.conf"
ACPID_LID_CONTENT='event=button/lid.* close
action=/usr/bin/loginctl suspend'

if [ -f "$ACPID_LID_FILE" ] && [ "$(cat "$ACPID_LID_FILE")" = "$ACPID_LID_CONTENT" ]; then
    log_success "acpid lid handler already in place at $ACPID_LID_FILE."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Will write $ACPID_LID_FILE (lid close → loginctl suspend)."
    else
        log_info "Writing acpid lid handler to $ACPID_LID_FILE"
        sudo install -d "$ACPID_EVENTS_DIR"
        echo "$ACPID_LID_CONTENT" | sudo tee "$ACPID_LID_FILE" > /dev/null
        log_success "Wrote $ACPID_LID_FILE — restart acpid (sv restart acpid) for it to pick up."
    fi
fi

log_success "=== SWAY COMPOSITOR STACK COMPLETE ==="
if [ "$DRY_RUN" = false ]; then
    log_info "Run ./setup-dotfiles.sh next to copy the sway/waybar/foot configs into your HOME."
    log_info "Then reboot and pick the 'Sway' session from the SDDM menu."
fi
