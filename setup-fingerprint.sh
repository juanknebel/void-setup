#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# --- Configuration ---
DRY_RUN=false
PACKAGES=(fprintd libfprint)
# UPEK Biometric Touchchip/Touchstrip USB ID for the ThinkPad X220.
UPEK_USB_ID="147e:2016"

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
    echo "Sets up the UPEK fingerprint reader on the X220 Tablet via fprintd."
    echo "PAM integration is intentionally NOT performed — opt in manually if desired,"
    echo "and always use 'auth sufficient pam_fprintd.so' (never solo-fingerprint: CVE-2024-37408)."
    echo ""
    echo "Options:"
    echo "  -d, --dry-run    Validate packages and hardware without modifications."
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
    log_info "=== INITIALIZING UPEK FINGERPRINT SETUP ==="
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# --- 1. Hardware Detection ---
# The UPEK reader on the X220 Tablet can be disabled in BIOS → Security →
# Fingerprint. If lsusb does not show 147e:2016, the package install still
# runs but enrollment will fail until the reader is enabled.
log_info "Probing for UPEK fingerprint reader (USB ID $UPEK_USB_ID)..."
if command -v lsusb > /dev/null 2>&1 && lsusb | grep -qi "$UPEK_USB_ID"; then
    log_success "UPEK reader detected on USB bus."
else
    log_warn "UPEK reader NOT detected. Check BIOS → Security → Fingerprint."
    log_warn "Continuing with package install — enrollment will fail until the reader is enabled."
fi

# --- 2. Package Installation ---
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
    log_success "All required fingerprint packages are satisfied."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Packages slated for installation: ${MISSING_PACKAGES[*]}"
    else
        log_info "Installing missing dependencies: ${MISSING_PACKAGES[*]}"
        sudo xbps-install -S "${MISSING_PACKAGES[@]}"
    fi
fi

# --- 3. Enrollment Status ---
# fprintd is D-Bus activated, so it will spawn on demand. If no fingers are
# enrolled for the current user, we print the manual enrollment instructions.
log_info "Checking enrollment status for user '$USER'..."
if [ "$DRY_RUN" = true ]; then
    log_warn "[Dry-Run] Would check enrollment via 'fprintd-list $USER'."
elif ! command -v fprintd-list > /dev/null 2>&1; then
    log_warn "fprintd-list not available yet (install pending or PATH issue)."
elif fprintd-list "$USER" 2>/dev/null | grep -q 'fingers found:'; then
    log_success "Fingerprints already enrolled for $USER:"
    fprintd-list "$USER" 2>/dev/null | sed 's/^/    /'
else
    log_warn "No fingerprints enrolled. To enroll, run:"
    log_warn "    fprintd-enroll"
    log_warn "Technique: slow, even swipe top-to-bottom, finger flat and centered,"
    log_warn "covering the entire strip. Fast swipes give 'enroll-swipe-too-short'."
    log_warn "Verify after enrollment with: fprintd-verify"
fi

log_success "=== FINGERPRINT SETUP COMPLETE ==="
if [ "$DRY_RUN" = false ]; then
    log_info "If you want sudo / lock-screen integration, edit /etc/pam.d/sudo (etc.)"
    log_info "and add: auth sufficient pam_fprintd.so   ← above the existing auth lines."
    log_info "NEVER use 'auth required pam_fprintd.so' alone — CVE-2024-37408."
fi
