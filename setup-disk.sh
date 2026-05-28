#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# Pre-install disk preparation: interactive cfdisk + automated mkfs and
# mount, ready for `void-installer` to take over. Runs from the live ISO
# (or any rescue environment) on the target disk.
#
# Workflow:
#   1. Probe the target device, refuse if any partition is mounted.
#   2. Drop into cfdisk so YOU pick the layout (typical X61: 512M /boot
#      + rest ext4 root, no swap partition — zram handles that later).
#   3. After you quit cfdisk, prompt for which partition is /boot and
#      which is root, format both (ext4), and mount under /mnt
#      ready for the installer.
#
# BIOS/MBR layout — the X61 Tablet has no UEFI firmware:
#   - /boot partition: ext4, 512 MB, bootable flag set
#   - /     partition: ext4, rest of disk
# GRUB is installed to the MBR by void-installer (not here).
#
# Swap is handled separately: post-install via setup-zram.sh
# (--with-swapfile if you want an HDD backstop on top of zram).

# --- Configuration ---
DRY_RUN=false
DEVICE=""

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
    echo "Usage: $0 [OPTIONS] <device>"
    echo "Partition (interactively via cfdisk), format, and mount a disk for void-installer."
    echo ""
    echo "Arguments:"
    echo "  <device>         Target block device, e.g. /dev/sda"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run    Print intended actions without touching the disk."
    echo "  -h, --help       Show this help message."
    echo ""
    echo "Expected layout after cfdisk (you set it manually):"
    echo "  - First partition  : ~512 MB, type 'Linux', bootable flag ON  → mkfs.ext4, mounted at /mnt/boot"
    echo "  - Second partition : rest of disk, type 'Linux filesystem'    → mkfs.ext4, mounted at /mnt"
    echo ""
    echo "GRUB is installed to the MBR by void-installer — no EFI partition needed."
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run) DRY_RUN=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        -*) log_err "Unknown option: $1"; show_help; exit 1 ;;
        *) DEVICE="$1"; shift ;;
    esac
done

if [ -z "$DEVICE" ]; then
    log_err "Target device is required (e.g. /dev/sda)."
    show_help
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    log_err "$DEVICE is not a block device."
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
    log_warn "=== RUNNING IN DRY-RUN MODE (NO CHANGES WILL BE MADE) ==="
elif [ "$EUID" -ne 0 ]; then
    log_err "This script must run as root (no sudo prompting in live ISO context)."
    exit 1
fi

# --- 1. Tool & Mount Sanity Checks ---
log_info "Verifying required tools..."
for tool in cfdisk mkfs.ext4 lsblk findmnt; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        log_err "Required tool '$tool' is not available."
        exit 1
    fi
done
log_success "All required tools are available."

log_info "Checking that no partition on $DEVICE is currently mounted..."
mounted_parts=$(lsblk -nrpo NAME,MOUNTPOINT "$DEVICE" | awk '$2 != "" {print $1 " on " $2}' || true)
if [ -n "$mounted_parts" ]; then
    log_err "These partitions are mounted — unmount first:"
    echo "$mounted_parts" | sed 's/^/    /'
    exit 1
fi
log_success "$DEVICE is unmounted."

# --- 2. Current Layout + Confirmation ---
log_info "Current layout of $DEVICE:"
lsblk -p "$DEVICE" | sed 's/^/    /'

cat <<WARN

${RED}WARNING:${NC} The next step lets you EDIT THE PARTITION TABLE of $DEVICE.
Any data on this disk can be lost depending on the choices you make in cfdisk.
Press Enter to launch cfdisk, or Ctrl+C to abort.
WARN

if [ "$DRY_RUN" = true ]; then
    log_warn "[Dry-Run] Would prompt for Enter, then launch: cfdisk $DEVICE"
    log_warn "[Dry-Run] Then prompt for /boot partition (e.g. ${DEVICE}1) and root (e.g. ${DEVICE}2),"
    log_warn "[Dry-Run] run mkfs.ext4 on both, mount root at /mnt, and mount /boot at /mnt/boot."
    exit 0
fi

read -r _

# --- 3. Interactive Partitioning ---
log_info "Launching cfdisk on $DEVICE — use DOS label; create a 512M Linux partition"
log_info "(mark bootable) for /boot and a Linux filesystem partition for root. Write, Quit."
cfdisk "$DEVICE"

log_info "Updated layout:"
lsblk -p "$DEVICE" | sed 's/^/    /'

# --- 4. Identify /boot and Root ---
echo ""
read -rp "Which partition is /boot (~512M, bootable flag set)? e.g. ${DEVICE}1: " BOOT_PART
read -rp "Which partition is the root filesystem?               e.g. ${DEVICE}2: " ROOT_PART

for p in "$BOOT_PART" "$ROOT_PART"; do
    if [ ! -b "$p" ]; then
        log_err "$p is not a block device. Aborting before any formatting."
        exit 1
    fi
done

if [ "$BOOT_PART" = "$ROOT_PART" ]; then
    log_err "/boot and root cannot be the same partition."
    exit 1
fi

# --- 5. Format ---
echo ""
log_warn "About to format:"
log_warn "    $BOOT_PART → mkfs.ext4 (will be mounted as /boot)"
log_warn "    $ROOT_PART → mkfs.ext4 (will be mounted as /)"
read -rp "Type 'yes' to continue: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log_err "Confirmation not received — aborting."
    exit 1
fi

mkfs.ext4 "$BOOT_PART"
log_success "Formatted $BOOT_PART as ext4."

mkfs.ext4 "$ROOT_PART"
log_success "Formatted $ROOT_PART as ext4."

# --- 6. Mount ---
log_info "Mounting $ROOT_PART at /mnt..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
log_info "Mounting $BOOT_PART at /mnt/boot..."
mount "$BOOT_PART" /mnt/boot

log_success "=== DISK PREPARATION COMPLETE ==="
log_info "Mount summary:"
findmnt /mnt /mnt/boot | sed 's/^/    /'
log_info ""
log_info "Next: run 'void-installer'. When asked about filesystems, keep the existing"
log_info "mounts (do NOT format again). Pick $BOOT_PART → ext4 → /boot,"
log_info "$ROOT_PART → ext4 → /. Select GRUB (legacy BIOS) as the bootloader."
log_info "Skip the swap step in the installer — swap is handled later by setup-zram.sh."
