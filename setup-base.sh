#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# Common system base for any desktop environment (Sway or Plasma).
# Installs: NetworkManager, SDDM stack, audio (PipeWire), Bluetooth,
# input stack (libinput/libwacom), fonts, Qt theming, shell stack,
# CLI tooling, and file managers. Wires up runit services and writes
# /etc/environment + SDDM theme + PipeWire drop-ins.
#
# Run this BEFORE the DE-specific scripts (setup-sway.sh, setup-plasma.sh).

# --- Configuration ---
DRY_RUN=false
PACKAGES=(
    # Network
    NetworkManager
    # X11 compatibility (SDDM greeter still runs in X; Xwayland for X11
    # apps under Wayland sessions). Without mesa-dri the Intel HD 3000
    # has no driver and the greeter shows a black screen.
    xorg-minimal mesa-dri xorg-server-xwayland
    # Generic input stack — Wayland uses libinput directly; libwacom
    # provides proper digitizer detection for the X220 Tablet stylus.
    libinput libwacom
    # Session / authentication (login and polkit)
    sddm polkit elogind
    # PipeWire audio stack + Bluetooth daemon. bluez provides
    # /etc/sv/bluetoothd; libspa-bluetooth adds BT audio support to
    # PipeWire (without it BT pairs but audio fails).
    pipewire wireplumber rtkit bluez libspa-bluetooth
    # Fonts (Wayland apps fail to open without them; Nerd Font for
    # Waybar icons and prompt symbols).
    dejavu-fonts-ttf noto-fonts-ttf nerd-fonts-ttf
    # Shell stack + prompt. chsh is intentionally NOT performed — the
    # system shell stays as bash; terminals launch zsh on their own.
    zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting
    zsh-history-substring-search starship
    # Terminal + general-purpose CLI tools
    # jq = JSON parser (used, among other things, by the Claude Code statusline).
    alacritty tmux htop wget curl git neovim fastfetch jq
    # File managers
    # pcmanfm-qt = primary GUI (Qt6, lightweight, integrates with Breeze)
    # gvfs       = automount for USB drives and trash support
    # yazi       = backup TUI, launched with `yazi` from any terminal
    pcmanfm-qt gvfs yazi
    # Qt theming — without these, Qt apps render without icons and lack a coherent palette
    # breeze-icons = official KDE icon theme
    # qt6ct        = central control panel for Qt6 apps (icon theme, style, palette)
    # kvantum      = widget engine that respects SVG themes (Breeze included)
    breeze-icons qt6ct kvantum
    # GUI apps
    firefox
)
# rtkit is included in PACKAGES but its runit service is NOT enabled by
# default — it only quiets cosmetic "RTKit error: ServiceUnknown" warnings;
# audio works without it. Enable manually with: sudo ln -s /etc/sv/rtkit /var/service/
SERVICES=(dbus polkitd sddm bluetoothd NetworkManager)
# Old network stack services to unlink in favor of NetworkManager.
STALE_SERVICES=(dhcpcd wpa_supplicant)
REQUIRED_GROUPS=(video audio input storage wheel bluetooth network plugdev)

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
    echo "Provisions the common system base shared by Sway and Plasma."
    echo "Run before setup-sway.sh / setup-plasma.sh / setup-dotfiles.sh."
    echo ""
    echo "Options:"
    echo "  -d, --dry-run    Validate packages, services, and config without modifications."
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
    log_info "=== INITIALIZING COMMON SYSTEM BASE ==="
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# --- 1. User Groups Validation ---
log_info "Verifying user group assignments..."
for group in "${REQUIRED_GROUPS[@]}"; do
    if ! getent group "$group" > /dev/null 2>&1; then
        log_warn "Group '$group' does not exist on this system — skipping."
        continue
    fi
    if getent group "$group" | grep -q -E "\b${USER}\b"; then
        log_success "User is already a member of group: $group"
    else
        if [ "$DRY_RUN" = true ]; then
            log_warn "[Dry-Run] Missing assignment detected: User should be added to '$group'"
        else
            log_info "Adding user to group: $group"
            sudo usermod -aG "$group" "$USER"
        fi
    fi
done

# --- 2. Package Existence & Installation Validation ---
log_info "Checking Void Linux binary repositories via xbps..."
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
    log_success "All required base packages are satisfied."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Packages slated for installation: ${MISSING_PACKAGES[*]}"
    else
        log_info "Installing missing dependencies: ${MISSING_PACKAGES[*]}"
        sudo xbps-install -S "${MISSING_PACKAGES[@]}"
    fi
fi

# --- 3. Stale Services Cleanup ---
# NetworkManager replaces dhcpcd + wpa_supplicant. Unlink the old runit
# services before enabling NM so they do not race for the interface.
# wpa_supplicant the PACKAGE stays — NM uses it underneath for WPA.
log_info "Cleaning up stale runit services..."
for svc in "${STALE_SERVICES[@]}"; do
    LINK="/var/service/$svc"
    if [ -L "$LINK" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_warn "[Dry-Run] Stale service symlink will be removed: $LINK"
        else
            log_info "Unlinking stale service: $LINK"
            sudo rm -f "$LINK"
        fi
    else
        log_success "Stale service already disabled: $svc"
    fi
done

# --- 4. Runit System Services Symlink Validation ---
log_info "Evaluating runit services infrastructure..."
for service in "${SERVICES[@]}"; do
    TARGET="/etc/sv/$service"
    LINK="/var/service/$service"

    if [ ! -d "$TARGET" ]; then
        log_err "Runit source service directory '$TARGET' does not exist!"
        continue
    fi

    if [ -L "$LINK" ]; then
        ACTUAL="$(readlink "$LINK")"
        if [ "${ACTUAL%/}" = "$TARGET" ]; then
            log_success "Service link active and valid: $LINK -> $TARGET"
        else
            log_err "Symlink conflict: $LINK -> $ACTUAL (expected $TARGET)."
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            log_warn "[Dry-Run] Missing service symlink detected: $LINK should link to $TARGET"
        else
            log_info "Activating runit management link for: $service"
            sudo ln -sf "$TARGET" "$LINK"
        fi
    fi
done

# --- 5. SDDM Global Configurations Verification ---
# SDDM merges /etc/sddm.conf with every *.conf in /etc/sddm.conf.d/.
SDDM_CONF="/etc/sddm.conf"
SDDM_CONF_D="/etc/sddm.conf.d"
sddm_has_breeze() {
    grep -rqs "^Current=breeze" "$SDDM_CONF" "$SDDM_CONF_D" 2>/dev/null
}

if [ "$DRY_RUN" = true ]; then
    if sddm_has_breeze; then
        log_success "SDDM configuration already sets theme to 'breeze'."
    else
        log_warn "[Dry-Run] SDDM config needs theme update to 'breeze'."
    fi
else
    log_info "Updating SDDM theme parameters..."
    if sddm_has_breeze; then
        log_success "SDDM already on Breeze, leaving existing config untouched."
    elif [ -f "$SDDM_CONF" ] && [ -s "$SDDM_CONF" ]; then
        if grep -q "\[Theme\]" "$SDDM_CONF"; then
            sudo sed -i '/\[Theme\]/,/^\[/ s/^Current=.*/Current=breeze/' "$SDDM_CONF"
        else
            printf '\n[Theme]\nCurrent=breeze\n' | sudo tee -a "$SDDM_CONF" > /dev/null
        fi
    else
        sudo mkdir -p "$SDDM_CONF_D"
        printf '[Theme]\nCurrent=breeze\n' | sudo tee "$SDDM_CONF_D/10-theme.conf" > /dev/null
    fi
fi

# --- 6. PipeWire System Configuration Symlinks ---
# Enables WirePlumber and pipewire-pulse system-wide config.
log_info "Linking PipeWire system configuration drop-ins..."
PIPEWIRE_CONFD="/etc/pipewire/pipewire.conf.d"
PIPEWIRE_LINKS=(
    "/usr/share/examples/wireplumber/10-wireplumber.conf"
    "/usr/share/examples/pipewire/20-pipewire-pulse.conf"
)

if [ "$DRY_RUN" = true ] && [ ! -d "$PIPEWIRE_CONFD" ]; then
    log_warn "[Dry-Run] $PIPEWIRE_CONFD will be created."
elif [ ! -d "$PIPEWIRE_CONFD" ]; then
    sudo mkdir -p "$PIPEWIRE_CONFD"
fi

for src in "${PIPEWIRE_LINKS[@]}"; do
    dest="$PIPEWIRE_CONFD/$(basename "$src")"
    if [ ! -e "$src" ]; then
        log_err "PipeWire source missing: $src (is pipewire/wireplumber installed?)"
        continue
    fi
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        log_success "PipeWire drop-in already linked: $dest"
    elif [ -e "$dest" ]; then
        log_err "PipeWire drop-in conflict: $dest exists and is not the expected symlink."
    else
        if [ "$DRY_RUN" = true ]; then
            log_warn "[Dry-Run] Will symlink: $dest -> $src"
        else
            log_info "Symlinking $dest -> $src"
            sudo ln -s "$src" "$dest"
        fi
    fi
done

# --- 7. PipeWire User Autostart (runit has no user-services) ---
# Symlinks in ~/.config/autostart so PipeWire and its Pulse layer start
# at login. Without this, on Void/runit, audio does not come up automatically.
log_info "Reviewing PipeWire user autostart entries..."
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_LINKS=(
    "/usr/share/applications/pipewire.desktop"
    "/usr/share/applications/pipewire-pulse.desktop"
)

if [ ! -d "$AUTOSTART_DIR" ]; then
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] $AUTOSTART_DIR will be created."
    else
        mkdir -p "$AUTOSTART_DIR"
    fi
fi

for src in "${AUTOSTART_LINKS[@]}"; do
    dest="$AUTOSTART_DIR/$(basename "$src")"
    if [ ! -e "$src" ]; then
        log_err "Autostart source missing: $src (is pipewire installed?)"
        continue
    fi
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        log_success "Autostart entry already linked: $dest"
    elif [ -e "$dest" ]; then
        log_err "Autostart conflict: $dest exists and is not the expected symlink."
    else
        if [ "$DRY_RUN" = true ]; then
            log_warn "[Dry-Run] Will symlink: $dest -> $src"
        else
            log_info "Symlinking $dest -> $src"
            ln -s "$src" "$dest"
        fi
    fi
done

# --- 8. Stale Package Cleanup ---
# Once NetworkManager is supervised, dhcpcd is redundant. Only remove it
# when (a) installed, (b) its runit service is unlinked, (c) NM is supervised.
log_info "Reviewing stale packages..."
if ! xbps-query dhcpcd > /dev/null 2>&1; then
    log_success "dhcpcd package already absent."
elif [ -L "/var/service/dhcpcd" ]; then
    log_warn "dhcpcd still has an active runit symlink — leaving package alone."
elif [ ! -L "/var/service/NetworkManager" ]; then
    log_warn "NetworkManager not supervised yet — leaving dhcpcd in place as a safety net."
elif xbps-query base-system > /dev/null 2>&1; then
    log_warn "Cannot remove dhcpcd while the 'base-system' meta-package is installed."
    log_warn "  Manual workaround (destructive — review first):"
    log_warn "    sudo xbps-install -Sy base-files && sudo xbps-remove -y base-system && sudo xbps-remove -y dhcpcd"
elif [ "$DRY_RUN" = true ]; then
    log_warn "[Dry-Run] dhcpcd package will be removed (NM is supervising the network)."
else
    log_info "Removing redundant dhcpcd package..."
    sudo xbps-remove -y dhcpcd
fi

# --- 9. Qt Platform Theme env ---
# Set QT_QPA_PLATFORMTHEME=qt6ct in /etc/environment so any Qt6 app picks
# up the centralized config from qt6ct: icon theme, widget style, color
# scheme. Has to live in /etc/environment (not ~/.zshrc) so PAM/elogind
# exports it BEFORE the WM starts — apps spawned from the WM don't source
# the user's shell rc.
log_info "Reviewing Qt platform theme env var..."
QT_ENV_LINE="QT_QPA_PLATFORMTHEME=qt6ct"
QT_ENV_FILE="/etc/environment"

if [ -f "$QT_ENV_FILE" ] && grep -qx "$QT_ENV_LINE" "$QT_ENV_FILE"; then
    log_success "Qt platform theme already set in $QT_ENV_FILE."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Will append '$QT_ENV_LINE' to $QT_ENV_FILE."
    else
        echo "$QT_ENV_LINE" | sudo tee -a "$QT_ENV_FILE" > /dev/null
        log_success "Wrote $QT_ENV_LINE to $QT_ENV_FILE (effective after next login)."
    fi
fi

log_success "=== COMMON SYSTEM BASE COMPLETE ==="
if [ "$DRY_RUN" = false ]; then
    log_info "Next: run ./setup-sway.sh and/or ./setup-plasma.sh, then ./setup-dotfiles.sh."
    log_info "Optional: ./setup-zram.sh ./setup-fingerprint.sh ./setup-virtualkb.sh ./setup-voidsplash.sh"
fi
