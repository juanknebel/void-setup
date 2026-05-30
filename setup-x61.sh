#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# ThinkPad X61 Tablet hardware add-on.
# Installs and configures:
#   - Wacom ISD300 digitizer driver (pen + eraser)
#   - TLP power management (battery charge thresholds, WiFi power)
#   - thinkfan fan speed control
#   - hdapsd HDAPS disk protection daemon (runit service authored here:
#     the Void package ships no service unit)
#   - acpi_call kernel module via DKMS (for ACPI battery threshold scripting)
#
# Assumes setup-base.sh and setup-i3.sh have already run.
# Can be re-run (idempotent): configs are only written when absent.

# --- Configuration ---
DRY_RUN=false
# HAS_HDD: empty = ask interactively (default), true/false set by --hdd/--ssd.
# Gates whether hdapsd disk-shock protection is installed and enabled.
HAS_HDD=""
PACKAGES=(
    # Wacom ISD300 pen digitizer driver for X11
    xf86-input-wacom
    # libwacom: device database so libinput identifies the tablet correctly
    libwacom
    # ThinkPad power management: battery thresholds, WiFi power save, etc.
    tlp
    # Fan speed control daemon (reads /proc/acpi/ibm/thermal)
    thinkfan
    # NOTE: hdapsd (HDD shock protection) is appended later, only when the
    # machine has a spinning disk — it has nothing to protect on an SSD.
    # ACPI call kernel module for battery charge threshold scripting.
    # Void packages this only as a DKMS module (no plain 'acpi_call' package).
    acpi_call-dkms
    # DKMS + kernel headers so acpi_call-dkms can build against the running
    # kernel. linux-headers tracks the 'linux' metapackage; if you boot a
    # different kernel series (e.g. linux-lts), install its matching headers.
    dkms
    linux-headers
    # Stylus note-taking and PDF annotation app with native Wacom support
    xournalpp
)

# hdapsd is appended after the SSD/HDD question is resolved (see below).
SERVICES=(tlp thinkfan)

REQUIRED_PREREQS=(xorg-minimal libinput)

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
    echo "Configures ThinkPad X61 Tablet hardware (Wacom, TLP, thinkfan, HDAPS)."
    echo "Run setup-base.sh and setup-i3.sh first."
    echo ""
    echo "Options:"
    echo "  -d, --dry-run    Print intended actions without modifying the system."
    echo "      --hdd        This machine has a spinning HDD: enable hdapsd."
    echo "      --ssd        This machine has an SSD: skip/disable hdapsd."
    echo "  -h, --help       Show this help message."
    echo ""
    echo "Without --hdd/--ssd the script asks interactively (disk type is"
    echo "autodetected and offered as the default answer)."
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run) DRY_RUN=true; shift ;;
        --hdd) HAS_HDD=true; shift ;;
        --ssd) HAS_HDD=false; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) log_err "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    log_warn "=== RUNNING IN DRY-RUN MODE (NO CHANGES WILL BE MADE) ==="
else
    log_info "=== INITIALIZING X61 TABLET HARDWARE STACK ==="
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# --- 0. Disk type (gates hdapsd) ---
# hdapsd parks the head of a spinning disk on shock; on an SSD there is
# nothing to park, and hdapsd would exit (runit restart loop) if no rotating
# disk is found. Autodetect a sensible default from /sys/block/*/rotational.
autodetect_hdd() {
    local f dev
    for f in /sys/block/*/queue/rotational; do
        [ -r "$f" ] || continue
        dev="$(basename "$(dirname "$(dirname "$f")")")"
        case "$dev" in loop*|ram*|zram*|sr*|dm-*) continue ;; esac
        [ "$(cat "$f")" = "1" ] && { echo "true"; return; }
    done
    echo "false"
}

if [ -z "$HAS_HDD" ]; then
    DEFAULT_HDD="$(autodetect_hdd)"
    if [ "$DEFAULT_HDD" = "true" ]; then
        PROMPT="Does this X61 have a spinning HDD? (autodetected: HDD) [Y/n] "
    else
        PROMPT="Does this X61 have a spinning HDD? (autodetected: SSD) [y/N] "
    fi
    read -r -p "$PROMPT" REPLY < /dev/tty || REPLY=""
    REPLY="${REPLY:-$DEFAULT_HDD}"
    case "$REPLY" in
        [Yy]*|true)  HAS_HDD=true ;;
        *)           HAS_HDD=false ;;
    esac
fi

if [ "$HAS_HDD" = true ]; then
    log_info "Disk type: HDD — hdapsd disk protection will be enabled."
    PACKAGES+=(hdapsd)
    SERVICES+=(hdapsd)
else
    log_info "Disk type: SSD — hdapsd will be skipped (nothing to protect)."
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
    log_err "Run ./setup-base.sh first."
    exit 1
fi

# --- 2. Package Installation ---
log_info "Checking X61 hardware packages against xbps..."
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
    log_success "All X61 hardware packages are satisfied."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Packages slated for installation: ${MISSING_PACKAGES[*]}"
    else
        log_info "Installing missing X61 packages: ${MISSING_PACKAGES[*]}"
        sudo xbps-install -S "${MISSING_PACKAGES[@]}"
    fi
fi

# --- 3. Wacom Xorg Input Class ---
WACOM_CONF="/etc/X11/xorg.conf.d/70-wacom.conf"
if [ -f "$WACOM_CONF" ]; then
    log_success "Wacom xorg config already present: $WACOM_CONF"
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Would write Wacom InputClass to $WACOM_CONF"
    else
        sudo mkdir -p /etc/X11/xorg.conf.d
        sudo tee "$WACOM_CONF" > /dev/null <<'EOF'
Section "InputClass"
    Identifier  "Wacom X61 Tablet"
    MatchProduct "Wacom ISD"
    MatchDevicePath "/dev/input/event*"
    Driver      "wacom"
EndSection
EOF
        log_success "Wrote $WACOM_CONF"
    fi
fi

# --- 4. thinkfan Configuration ---
# Conservative fan curve for the X61 Core 2 Duo.
# Temperatures are in °C; thinkfan reads /proc/acpi/ibm/thermal.
# Fan levels: 0=off, 1-7=increasing speed, 127=full/disengaged.
# Tune these thresholds on your unit — the X61 runs warm by default.
THINKFAN_CONF="/etc/thinkfan.conf"
if [ -f "$THINKFAN_CONF" ]; then
    log_success "thinkfan config already present: $THINKFAN_CONF"
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Would write thinkfan config to $THINKFAN_CONF"
    else
        sudo tee "$THINKFAN_CONF" > /dev/null <<'EOF'
# thinkfan.conf — ThinkPad X61 Tablet
# Sensor: /proc/acpi/ibm/thermal index 0 = CPU temperature (°C)
tp_fan /proc/acpi/ibm/fan
tp_thermal /proc/acpi/ibm/thermal (0, 1)

# (level, low_threshold, high_threshold)
(0,   0,  50)
(2,  48,  58)
(4,  56,  66)
(7,  64,  74)
(127, 72, 32767)
EOF
        log_success "Wrote $THINKFAN_CONF"
    fi
fi

# --- 5. TLP Configuration ---
TLP_CONF="/etc/tlp.conf"
if [ -f "$TLP_CONF" ] && grep -q "START_CHARGE_THRESH_BAT0" "$TLP_CONF"; then
    log_success "TLP config already has charge thresholds: $TLP_CONF"
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Would write TLP charge thresholds to $TLP_CONF"
    else
        sudo tee "$TLP_CONF" > /dev/null <<'EOF'
# tlp.conf — ThinkPad X61 Tablet
# Battery charge thresholds: start charging at 40%, stop at 80%.
# Extends battery cycle life significantly on older cells.
START_CHARGE_THRESH_BAT0=40
STOP_CHARGE_THRESH_BAT0=80

# Disable WiFi power saving (causes connection drops on older cards)
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=off

# CPU scaling governor
CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_SCALING_GOVERNOR_ON_BAT=powersave
EOF
        log_success "Wrote $TLP_CONF"
    fi
fi

# --- 6. acpi_call Module at Boot ---
MODULES_DIR="/etc/modules-load.d"
ACPI_MODULES_CONF="$MODULES_DIR/acpi_call.conf"
if [ -f "$ACPI_MODULES_CONF" ]; then
    log_success "acpi_call module load config already present."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Would write $ACPI_MODULES_CONF to auto-load acpi_call"
    else
        sudo mkdir -p "$MODULES_DIR"
        echo "acpi_call" | sudo tee "$ACPI_MODULES_CONF" > /dev/null
        log_success "Wrote $ACPI_MODULES_CONF (acpi_call loads at next boot)"
    fi
fi

# --- 6b. hdapsd runit service ---
# The Void hdapsd package ships no service unit. Author one here so the
# runit loop below can enable it. hdapsd autodetects all rotating disks and
# stays in the foreground unless --background is passed — ideal for runit.
# Only relevant on a spinning HDD (see the SSD/HDD question above).
HDAPSD_SVC="/etc/sv/hdapsd"
HDAPSD_LINK="/var/service/hdapsd"
if [ "$HAS_HDD" = true ]; then
    if [ -f "$HDAPSD_SVC/run" ]; then
        log_success "hdapsd runit service already present: $HDAPSD_SVC/run"
    else
        if [ "$DRY_RUN" = true ]; then
            log_warn "[Dry-Run] Would author runit service at $HDAPSD_SVC/run"
        else
            sudo mkdir -p "$HDAPSD_SVC"
            sudo tee "$HDAPSD_SVC/run" > /dev/null <<'EOF'
#!/bin/sh
# Run hdapsd in the foreground (no --background) so runit can supervise it.
# With no --device, hdapsd autodetects all rotational, non-removable disks.
exec hdapsd 2>&1
EOF
            sudo chmod +x "$HDAPSD_SVC/run"
            log_success "Authored runit service: $HDAPSD_SVC/run"
        fi
    fi
else
    # SSD: make sure a previously enabled hdapsd is deactivated.
    if [ -L "$HDAPSD_LINK" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_warn "[Dry-Run] Would deactivate hdapsd: remove $HDAPSD_LINK"
        else
            sudo rm -f "$HDAPSD_LINK"
            log_success "SSD: deactivated hdapsd (removed $HDAPSD_LINK)."
        fi
    else
        log_info "SSD: hdapsd not enabled — nothing to do."
    fi
fi

# --- 7. Runit Services ---
log_info "Enabling X61 hardware runit services..."
for service in "${SERVICES[@]}"; do
    TARGET="/etc/sv/$service"
    LINK="/var/service/$service"

    if [ ! -d "$TARGET" ]; then
        log_err "Runit service directory '$TARGET' does not exist — package missing?"
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

log_success "=== X61 TABLET HARDWARE STACK COMPLETE ==="
if [ "$DRY_RUN" = false ]; then
    log_warn "ACTION REQUIRED: Verify your Wacom device name before relying on screen rotation."
    log_warn "  Run: xinput list | grep -i wacom"
    log_warn "  If the name differs from 'Wacom ISD', set WACOM_DEVICE in ~/.local/bin/rotate_screen_x11.sh"
    log_info ""
    log_warn "acpi_call is a DKMS module: confirm it built against your kernel."
    log_warn "  Run: dkms status acpi_call   (and: modinfo acpi_call)"
    log_warn "  If it didn't build, install headers for your running kernel"
    log_warn "  (e.g. linux-lts-headers) and run: dkms autoinstall"
    log_info "The acpi_call module loads on next reboot via $ACPI_MODULES_CONF."
    log_info ""
    if [ "$HAS_HDD" = true ]; then
        log_info "hdapsd disk protection is enabled. Verify: sv status hdapsd"
    else
        log_info "hdapsd was skipped (SSD). Re-run with --hdd if you swap in an HDD."
    fi
    log_info "thinkfan and TLP configs are conservative defaults — tune them for your unit."
fi
