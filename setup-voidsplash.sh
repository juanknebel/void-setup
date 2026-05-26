#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# Installs voidsplash, a minimal boot splash for runit that draws PNG
# frames on the framebuffer via fbv (no Plymouth, no initramfs changes).
# Clones jaylesworth/voidsplash from GitHub, installs the binary, wires
# the runit service, and copies the bundled void-theme sample frames.
#
# The optional --grub-quiet flag also appends `console=tty2` to
# GRUB_CMDLINE_LINUX_DEFAULT so kernel messages do not paint over the
# splash. That step is opt-in because it touches GRUB.

# --- Configuration ---
DRY_RUN=false
GRUB_QUIET=false
PACKAGES=(fbv git ImageMagick)
REPO_URL="https://github.com/jaylesworth/voidsplash.git"
CLONE_DIR="/tmp/voidsplash"
BIN_DEST="/bin/voidsplash"
SERVICE_DIR="/etc/sv/voidsplash"
SERVICE_LINK="/var/service/voidsplash"
THEME_DIR="/etc/voidsplash"

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
    echo "Installs voidsplash (framebuffer boot splash for runit)."
    echo ""
    echo "Options:"
    echo "  -d, --dry-run     Validate without modifying anything."
    echo "  --grub-quiet      Also append 'console=tty2' to GRUB_CMDLINE_LINUX_DEFAULT"
    echo "                    so kernel logs render on tty2 instead of over the splash."
    echo "                    Touches /etc/default/grub and regenerates grub.cfg."
    echo "  -h, --help        Show this help message."
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run) DRY_RUN=true; shift ;;
        --grub-quiet) GRUB_QUIET=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) log_err "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    log_warn "=== RUNNING IN DRY-RUN MODE (NO CHANGES WILL BE MADE) ==="
else
    log_info "=== INITIALIZING VOIDSPLASH SETUP ==="
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# --- 1. Dependency Packages ---
log_info "Checking dependency packages..."
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
    log_success "All voidsplash dependencies are satisfied."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Packages slated for installation: ${MISSING_PACKAGES[*]}"
    else
        log_info "Installing missing dependencies: ${MISSING_PACKAGES[*]}"
        sudo xbps-install -S "${MISSING_PACKAGES[@]}"
    fi
fi

# --- 2. Clone voidsplash ---
log_info "Reviewing voidsplash sources at $CLONE_DIR..."
if [ -d "$CLONE_DIR/.git" ]; then
    log_success "Clone already present at $CLONE_DIR — skipping clone."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Will clone $REPO_URL into $CLONE_DIR."
    else
        log_info "Cloning $REPO_URL into $CLONE_DIR..."
        git clone "$REPO_URL" "$CLONE_DIR"
    fi
fi

# --- 3. Install Binary ---
log_info "Reviewing voidsplash binary at $BIN_DEST..."
if [ -x "$BIN_DEST" ]; then
    log_success "voidsplash binary already installed at $BIN_DEST."
elif [ "$DRY_RUN" = true ]; then
    log_warn "[Dry-Run] Will copy $CLONE_DIR/voidsplash -> $BIN_DEST and chmod +x."
elif [ ! -f "$CLONE_DIR/voidsplash" ]; then
    log_err "Expected $CLONE_DIR/voidsplash not found — clone may have failed."
    exit 1
else
    sudo install -m 0755 "$CLONE_DIR/voidsplash" "$BIN_DEST"
    log_success "Installed $BIN_DEST"
fi

# --- 4. Runit Service ---
log_info "Reviewing runit service at $SERVICE_DIR..."
if [ -f "$SERVICE_DIR/run" ]; then
    log_success "Service already exists at $SERVICE_DIR."
elif [ "$DRY_RUN" = true ]; then
    log_warn "[Dry-Run] Will create $SERVICE_DIR/run invoking $BIN_DEST."
else
    sudo mkdir -p "$SERVICE_DIR"
    # Minimal runit run script — voidsplash itself loops over the frames.
    printf '#!/bin/sh\nexec %s\n' "$BIN_DEST" | sudo tee "$SERVICE_DIR/run" > /dev/null
    sudo chmod +x "$SERVICE_DIR/run"
    log_success "Wrote $SERVICE_DIR/run"
fi

log_info "Reviewing runit service symlink at $SERVICE_LINK..."
if [ -L "$SERVICE_LINK" ]; then
    log_success "Service link already active: $SERVICE_LINK"
elif [ ! -d "$SERVICE_DIR" ]; then
    log_warn "Cannot link service — $SERVICE_DIR missing."
elif [ "$DRY_RUN" = true ]; then
    log_warn "[Dry-Run] Will link $SERVICE_LINK -> $SERVICE_DIR"
else
    sudo ln -sf "$SERVICE_DIR" "$SERVICE_LINK"
    log_success "Linked $SERVICE_LINK -> $SERVICE_DIR"
fi

# --- 5. Theme Frames ---
# Voidsplash plays PNG frames named void-0.png, void-1.png, ... from
# $THEME_DIR. The bundled void-theme/ inside the clone has sample frames.
log_info "Reviewing splash frames at $THEME_DIR..."
if compgen -G "$THEME_DIR/void-*.png" > /dev/null; then
    log_success "Frames already present in $THEME_DIR."
elif [ "$DRY_RUN" = true ]; then
    log_warn "[Dry-Run] Will copy $CLONE_DIR/void-theme/*.png -> $THEME_DIR"
elif [ ! -d "$CLONE_DIR/void-theme" ]; then
    log_warn "$CLONE_DIR/void-theme not found — drop your own void-*.png into $THEME_DIR manually."
else
    sudo mkdir -p "$THEME_DIR"
    sudo cp "$CLONE_DIR"/void-theme/*.png "$THEME_DIR/" 2>/dev/null || true
    log_success "Copied bundled sample frames to $THEME_DIR."
fi

# --- 6. Optional GRUB Quiet (--grub-quiet) ---
# Adds console=tty2 to GRUB_CMDLINE_LINUX_DEFAULT so kernel messages
# render on a separate VT instead of painting over the splash.
if [ "$GRUB_QUIET" = true ]; then
    GRUB_FILE="/etc/default/grub"
    log_info "Reviewing GRUB cmdline at $GRUB_FILE..."
    if [ ! -f "$GRUB_FILE" ]; then
        log_err "$GRUB_FILE not found — is GRUB the active bootloader?"
    elif grep -q 'GRUB_CMDLINE_LINUX_DEFAULT=.*console=tty2' "$GRUB_FILE"; then
        log_success "GRUB cmdline already contains console=tty2."
    elif [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Will append 'console=tty2' to GRUB_CMDLINE_LINUX_DEFAULT and run grub-mkconfig."
    else
        ts=$(date +%Y%m%d%H%M%S)
        sudo cp -a "$GRUB_FILE" "$GRUB_FILE.bak.$ts"
        log_info "Backed up $GRUB_FILE to $GRUB_FILE.bak.$ts"
        # Insert console=tty2 just before the closing quote of the existing value.
        sudo sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 console=tty2"/' "$GRUB_FILE"
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        log_success "Added console=tty2 and regenerated grub.cfg."
    fi
else
    log_info "GRUB cmdline NOT touched (re-run with --grub-quiet to push kernel logs to tty2)."
fi

log_success "=== VOIDSPLASH SETUP COMPLETE ==="
if [ "$DRY_RUN" = false ]; then
    log_info "Reboot to see the splash. To replace the sample frames with your own,"
    log_info "drop void-0.png, void-1.png, ... into $THEME_DIR (1280x800 for the X220 panel)."
fi
