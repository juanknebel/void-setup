#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# Sets up zram-based compressed swap (zramen) and tunes vm.swappiness.
# Optionally also creates a low-priority disk swapfile as OOM backstop.
#
# Defaults match the X220 Tablet profile (6 GB RAM + slow disk):
#   - zram at 50% of RAM with zstd compression, priority 32767
#   - vm.swappiness=100 so the kernel reaches for swap (zram) early
#   - swapfile NOT created by default (opt in with --with-swapfile)

# --- Configuration ---
DRY_RUN=false
WITH_SWAPFILE=false
SWAPFILE_PATH="/swapfile"
SWAPFILE_SIZE_MB=8192       # 8 GB
SWAPFILE_PRIORITY=10        # well below zram's 32767

PACKAGES=(zramen)
ZRAMEN_CONF_DIR="/etc/sv/zramen"
ZRAMEN_CONF="$ZRAMEN_CONF_DIR/conf"
ZRAM_SYSCTL="/etc/sysctl.d/99-zram.conf"
ZRAM_SYSCTL_LINE="vm.swappiness=100"

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
    echo "Sets up zram compressed swap + vm.swappiness, with optional disk swapfile."
    echo ""
    echo "Options:"
    echo "  -d, --dry-run        Validate config without modifications."
    echo "  --with-swapfile      Also create ${SWAPFILE_PATH} (${SWAPFILE_SIZE_MB} MB)"
    echo "                       at priority ${SWAPFILE_PRIORITY} as an anti-OOM backstop."
    echo "  -h, --help           Show this help message."
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run) DRY_RUN=true; shift ;;
        --with-swapfile) WITH_SWAPFILE=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) log_err "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    log_warn "=== RUNNING IN DRY-RUN MODE (NO CHANGES WILL BE MADE) ==="
else
    log_info "=== INITIALIZING ZRAM / SWAP STACK ==="
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# --- 1. zramen Package Installation ---
log_info "Checking zramen package..."
if xbps-query zramen > /dev/null 2>&1; then
    log_success "Package 'zramen' is already installed."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Will install zramen."
    else
        log_info "Installing zramen..."
        sudo xbps-install -S zramen
    fi
fi

# --- 2. zramen Daemon Configuration ---
# Write /etc/sv/zramen/conf BEFORE the service symlink is created so it
# starts with our settings on first activation. Enabling the service
# before writing the conf leaves zramen running with defaults (lz4 /
# 25% RAM) and requires a subsequent `sv restart zramen` to re-read.
log_info "Reviewing zramen daemon configuration..."
read -r -d '' ZRAMEN_CONF_CONTENT <<'EOF' || true
# /etc/sv/zramen/conf
# zramen configuration for the X220 Tablet (6 GB RAM + HDD).
# The service run script sources this file: [ -r ./conf ] && . ./conf ; zramen make

# Percentage of RAM to allocate to zram (NOT MB, a percentage).
# Default is 25 (~1.5 GB on 6 GB, too little). With 6 GB + HDD it pays
# off to push higher: 50% = ~3 GB of zram which compresses to more.
# Upstream help recommends <= 50.
export ZRAM_SIZE=50

# Compression algorithm.
# lz4  = fastest compress/decompress, lower ratio (default).
# zstd = better ratio (more effective RAM), slightly higher CPU cost.
# On Sandy Bridge lz4 is gentler on the CPU; zstd makes better use of RAM.
# Start with zstd for the better ratio; if the CPU suffers, switch to lz4.
export ZRAM_COMP_ALGORITHM=zstd

# Priority 32767 (max) is already the default; we set it explicitly so
# that zram is used BEFORE the swapfile on the HDD.
export ZRAM_PRIORITY=32767

# Discard: 'both' is the default and fine here (no encrypted swap).
export ZRAMEN_SWAPON_DISCARD=both
EOF

if [ -f "$ZRAMEN_CONF" ] && [ "$(cat "$ZRAMEN_CONF" 2>/dev/null)" = "$ZRAMEN_CONF_CONTENT" ]; then
    log_success "zramen conf already matches expected content."
elif [ ! -d "$ZRAMEN_CONF_DIR" ]; then
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] $ZRAMEN_CONF_DIR missing — install zramen first."
    else
        log_err "$ZRAMEN_CONF_DIR does not exist (is zramen installed?)."
    fi
else
    if [ "$DRY_RUN" = true ]; then
        if [ -f "$ZRAMEN_CONF" ]; then
            log_warn "[Dry-Run] Existing $ZRAMEN_CONF differs and will be backed up + replaced."
        else
            log_warn "[Dry-Run] $ZRAMEN_CONF will be created."
        fi
    else
        if [ -f "$ZRAMEN_CONF" ]; then
            ts=$(date +%Y%m%d%H%M%S)
            sudo cp -a "$ZRAMEN_CONF" "$ZRAMEN_CONF.bak.$ts"
            log_info "Backed up existing conf to $ZRAMEN_CONF.bak.$ts"
        fi
        printf '%s\n' "$ZRAMEN_CONF_CONTENT" | sudo tee "$ZRAMEN_CONF" > /dev/null
        log_success "Wrote $ZRAMEN_CONF"
        if [ -L "/var/service/zramen" ]; then
            sudo sv restart zramen || true
            log_info "Restarted zramen to apply new conf."
        fi
    fi
fi

# --- 3. zramen Runit Service Symlink ---
log_info "Reviewing zramen runit service symlink..."
ZRAMEN_LINK="/var/service/zramen"
if [ -L "$ZRAMEN_LINK" ]; then
    log_success "zramen service link already active."
elif [ ! -d "$ZRAMEN_CONF_DIR" ]; then
    log_warn "Cannot link zramen service — $ZRAMEN_CONF_DIR missing."
elif [ "$DRY_RUN" = true ]; then
    log_warn "[Dry-Run] Will link $ZRAMEN_LINK -> $ZRAMEN_CONF_DIR"
else
    sudo ln -sf "$ZRAMEN_CONF_DIR" "$ZRAMEN_LINK"
    log_success "Linked $ZRAMEN_LINK -> $ZRAMEN_CONF_DIR"
fi

# --- 4. zram Sysctl Tuning ---
# vm.swappiness=100 tells the kernel to use swap aggressively. With zram
# in RAM (priority 32767) that means we lean on compressed memory before
# any disk swap.
log_info "Reviewing zram sysctl tuning..."
if [ -f "$ZRAM_SYSCTL" ] && grep -qx "$ZRAM_SYSCTL_LINE" "$ZRAM_SYSCTL"; then
    log_success "zram sysctl already in place: $ZRAM_SYSCTL"
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Will write $ZRAM_SYSCTL with '$ZRAM_SYSCTL_LINE'."
    else
        sudo mkdir -p "$(dirname "$ZRAM_SYSCTL")"
        echo "$ZRAM_SYSCTL_LINE" | sudo tee "$ZRAM_SYSCTL" > /dev/null
        sudo sysctl --system > /dev/null
        log_success "Wrote $ZRAM_SYSCTL and reloaded sysctl."
    fi
fi

# --- 5. Optional Disk Swapfile (--with-swapfile) ---
# Creates a low-priority swapfile so the kernel only falls back to disk
# when zram is fully consumed. Useful for browser-heavy workloads.
if [ "$WITH_SWAPFILE" = true ]; then
    log_info "Reviewing disk swapfile at $SWAPFILE_PATH..."
    if grep -q "^$SWAPFILE_PATH" /etc/fstab 2>/dev/null; then
        log_success "Swapfile already listed in /etc/fstab — skipping setup."
    else
        if [ "$DRY_RUN" = true ]; then
            if [ -f "$SWAPFILE_PATH" ]; then
                log_warn "[Dry-Run] $SWAPFILE_PATH exists — will activate + add to fstab (pri=$SWAPFILE_PRIORITY)."
            else
                log_warn "[Dry-Run] Will create $SWAPFILE_PATH (${SWAPFILE_SIZE_MB} MB), activate, and add to fstab."
            fi
        else
            if [ ! -f "$SWAPFILE_PATH" ]; then
                log_info "Creating $SWAPFILE_PATH (${SWAPFILE_SIZE_MB} MB) — this may take a minute..."
                sudo dd if=/dev/zero of="$SWAPFILE_PATH" bs=1M count="$SWAPFILE_SIZE_MB" status=progress
                sudo chmod 600 "$SWAPFILE_PATH"
                sudo mkswap "$SWAPFILE_PATH"
            else
                log_info "$SWAPFILE_PATH already exists — reusing."
            fi
            sudo swapon --priority "$SWAPFILE_PRIORITY" "$SWAPFILE_PATH" || true
            echo "$SWAPFILE_PATH none swap sw,pri=$SWAPFILE_PRIORITY 0 0" | sudo tee -a /etc/fstab > /dev/null
            log_success "Swapfile active (pri=$SWAPFILE_PRIORITY) and persisted in /etc/fstab."
        fi
    fi
else
    log_info "Disk swapfile NOT configured (re-run with --with-swapfile to opt in)."
fi

log_success "=== ZRAM / SWAP STACK COMPLETE ==="
if [ "$DRY_RUN" = false ]; then
    log_info "Verify with: zramctl ; swapon --show ; free -h"
fi
