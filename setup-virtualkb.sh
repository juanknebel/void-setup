#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# --- Configuration ---
DRY_RUN=false
ENABLE_SDDM=false
PACKAGES=(maliit-framework maliit-keyboard)
SDDM_VKBD_CONF="/etc/sddm.conf.d/10-virtualkbd.conf"

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
    echo "Installs the Maliit virtual keyboard for Plasma Wayland sessions."
    echo "For Sway, wvkbd is the chosen on-screen keyboard (already in setup-system.sh"
    echo "and bound to Mod+Shift+T in dotfiles/sway/config)."
    echo ""
    echo "Options:"
    echo "  -d, --dry-run     Validate packages and config without modifications."
    echo "  --enable-sddm     Also enable qtvirtualkeyboard at the SDDM greeter."
    echo "                    NOTE: SDDM config tweaks have hung the X220 in the past;"
    echo "                    keep a TTY ready (Ctrl+Alt+F3) when applying."
    echo "  -h, --help        Show this help message."
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run) DRY_RUN=true; shift ;;
        --enable-sddm) ENABLE_SDDM=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) log_err "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    log_warn "=== RUNNING IN DRY-RUN MODE (NO CHANGES WILL BE MADE) ==="
else
    log_info "=== INITIALIZING VIRTUAL KEYBOARD SETUP ==="
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# --- 1. Package Installation ---
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
    log_success "All required virtual-keyboard packages are satisfied."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Packages slated for installation: ${MISSING_PACKAGES[*]}"
    else
        log_info "Installing missing dependencies: ${MISSING_PACKAGES[*]}"
        sudo xbps-install -S "${MISSING_PACKAGES[@]}"
    fi
fi

# --- 2. SDDM Greeter Virtual Keyboard (opt-in via --enable-sddm) ---
# SDDM's [General] InputMethod=qtvirtualkeyboard makes the Qt virtual keyboard
# available at the login screen. qt6-virtualkeyboard usually ships as a dep of
# Plasma, so only the config is needed.
if [ "$ENABLE_SDDM" = true ]; then
    log_info "Configuring SDDM greeter virtual keyboard at $SDDM_VKBD_CONF..."
    EXPECTED_CONTENT=$'[General]\nInputMethod=qtvirtualkeyboard'

    if [ -f "$SDDM_VKBD_CONF" ] && [ "$(cat "$SDDM_VKBD_CONF" 2>/dev/null)" = "$EXPECTED_CONTENT" ]; then
        log_success "SDDM virtual keyboard config already in place."
    else
        if [ "$DRY_RUN" = true ]; then
            if [ -f "$SDDM_VKBD_CONF" ]; then
                log_warn "[Dry-Run] Existing $SDDM_VKBD_CONF differs and will be backed up + replaced."
            else
                log_warn "[Dry-Run] $SDDM_VKBD_CONF will be created."
            fi
        else
            sudo mkdir -p "$(dirname "$SDDM_VKBD_CONF")"
            if [ -f "$SDDM_VKBD_CONF" ]; then
                ts=$(date +%Y%m%d%H%M%S)
                sudo cp -a "$SDDM_VKBD_CONF" "$SDDM_VKBD_CONF.bak.$ts"
                log_info "Backed up existing config to $SDDM_VKBD_CONF.bak.$ts"
            fi
            printf '%s\n' "$EXPECTED_CONTENT" | sudo tee "$SDDM_VKBD_CONF" > /dev/null
            log_success "Wrote $SDDM_VKBD_CONF"
            log_warn "Test by logging out — keep TTY (Ctrl+Alt+F3) ready in case the greeter hangs."
        fi
    fi
else
    log_info "SDDM greeter virtual keyboard NOT configured (re-run with --enable-sddm to opt in)."
fi

log_success "=== VIRTUAL KEYBOARD SETUP COMPLETE ==="
if [ "$DRY_RUN" = false ]; then
    log_info "Inside a Plasma Wayland session, enable Maliit via:"
    log_info "    System Settings → Input Devices → Virtual Keyboard → Maliit"
    log_info "(This section only appears under Wayland, not X11.)"
fi
