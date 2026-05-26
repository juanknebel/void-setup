#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# --- Configuration & Theme Variables ---
DRY_RUN=false
PACKAGES=(
    # Network
    NetworkManager
    # X11 compatibility (SDDM greeter still runs in X; Xwayland for X11 apps
    # under Wayland sessions). Without mesa-dri the Intel HD 3000 has no
    # driver and the greeter shows a black screen (install notes 7.2).
    xorg-minimal mesa-dri xorg-server-xwayland
    # Sway compositor + window utilities
    sway swaybg swaylock swayidle Waybar fuzzel mako wlr-randr
    # Screenshots + clipboard (Wayland-native stack)
    # grim = capture · slurp = region select · satty = annotate · wl-clipboard = wl-copy/wl-paste
    grim slurp satty wl-clipboard
    # Terminal + virtual keyboard + tablet
    foot wvkbd
    # Generic input stack (tablet/stylus) — Wayland uses libinput directly,
    # libwacom provides proper digitizer detection (install notes 7.5).
    libinput libwacom
    # Session / authentication (login and polkit)
    sddm polkit elogind
    # PipeWire audio stack + Bluetooth daemon (included even though the
    # install notes cover them, so that setup-system.sh is runnable on a fresh
    # install). bluez provides /etc/sv/bluetoothd; libspa-bluetooth adds
    # BT audio support to PipeWire (without it BT pairs but audio fails).
    pipewire wireplumber rtkit bluez libspa-bluetooth
    # Hardware controls — TUIs for managing audio/Bluetooth and CLI for backlight
    pulsemixer bluetui brightnessctl
    # Fonts (Wayland apps fail to open without them; Nerd Font for Waybar
    # icons and prompt symbols).
    dejavu-fonts-ttf noto-fonts-ttf nerd-fonts-ttf
    # Tablet bezel button identification under Wayland
    wev evtest
    # UPEK fingerprint reader (install notes 9). PAM integration NOT enabled.
    fprintd libfprint
    # Shell stack + prompt. chsh is intentionally NOT performed — the system
    # shell stays as bash; Alacritty launches zsh on its own (see install
    # notes 12 and the alacritty.toml header comment).
    zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting
    zsh-history-substring-search starship
    # Terminal + general-purpose CLI tools
    # jq = JSON parser (lo usa, entre otras cosas, el statusline de Claude Code).
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
    # Compressed RAM swap (install notes 13)
    zramen
)
# Note: the Breeze SDDM theme ships with plasma-desktop on Void; there is no
# separate sddm-theme-breeze package in the repos.
# rtkit is intentionally NOT in this list: install notes 7.4 mark it as
# optional (only quiets cosmetic "RTKit error: ServiceUnknown" warnings;
# audio works without it). The package stays in PACKAGES so the service
# can be enabled by hand later if desired.
SERVICES=(dbus elogind polkitd sddm bluetoothd NetworkManager zramen)
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
    echo "Options:"
    echo "  -d, --dry-run    Validate packages, directories, and symlinks without modifications."
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
    log_info "=== INITIALIZING PLASMATIC SWAY DEPLOYMENT ==="
    # Cache sudo privileges upfront
    sudo -v
    # Keep-alive sudo loop during execution
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# --- 1. User Groups Validation ---
log_info "Verifying user group assignments..."
for group in "${REQUIRED_GROUPS[@]}"; do
    # Skip groups that do not exist on this distro (e.g. 'power' exists on
    # Arch but not Void) — otherwise usermod -aG would fail and set -e
    # would kill the whole run.
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
    # xbps-query <pkg> returns 0 if the package is installed
    if xbps-query "$pkg" > /dev/null 2>&1; then
        log_success "Package '$pkg' is already installed. Skipping."
    else
        # xbps-query -R <pkg> does an exact lookup against remote repos
        # (-Rs is a substring search and returns 0 even with zero matches).
        if xbps-query -R "$pkg" > /dev/null 2>&1; then
            log_warn "Package '$pkg' is missing but available in repositories."
            MISSING_PACKAGES+=("$pkg")
        else
            log_err "Package '$pkg' was not found in active Void repositories! Check repository sync."
        fi
    fi
done

# Act on collected missing packages
if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
    log_success "All required system software packages are satisfied."
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Software packages slated for installation: ${MISSING_PACKAGES[*]}"
    else
        log_info "Installing missing dependencies: ${MISSING_PACKAGES[*]}"
        sudo xbps-install -S "${MISSING_PACKAGES[@]}"
    fi
fi

# --- 3. Stale Services Cleanup ---
# NetworkManager replaces dhcpcd + wpa_supplicant. Unlink the old runit
# services before enabling NM so they do not race for the interface
# (install notes 4 + 6). wpa_supplicant the PACKAGE stays — NM uses it
# underneath for WPA — only its standalone service is disabled here.
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

# --- 4. zramen Daemon Configuration ---
# Write /etc/sv/zramen/conf before the service is symlinked so it starts
# with our settings on first activation. The install notes 13 warn that
# enabling the service before writing the conf leaves zramen running with
# defaults (lz4 / 25% RAM) and requires a subsequent `sv restart zramen`.
log_info "Reviewing zramen daemon configuration..."
ZRAMEN_CONF_DIR="/etc/sv/zramen"
ZRAMEN_CONF="$ZRAMEN_CONF_DIR/conf"
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
        # If the service is already supervised (re-runs), reload to pick the new conf.
        if [ -L "/var/service/zramen" ]; then
            sudo sv restart zramen || true
            log_info "Restarted zramen to apply new conf."
        fi
    fi
fi

# --- 5. Runit System Services Symlink Validation ---
log_info "Evaluating runit services infrastructure..."
for service in "${SERVICES[@]}"; do
    TARGET="/etc/sv/$service"
    LINK="/var/service/$service"
    
    if [ ! -d "$TARGET" ]; then
        log_err "Runit source service directory '$TARGET' does not exist! Installation error."
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

# --- 6. SDDM Global Configurations Verification ---
# SDDM merges /etc/sddm.conf with every *.conf in /etc/sddm.conf.d/, so the
# theme can legitimately live in either location (e.g. sddm-kcm writes to
# /etc/sddm.conf.d/kde_settings.conf when "Apply Plasma Settings" is used).
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
            echo -e "\n[Theme]\nCurrent=breeze" | sudo tee -a "$SDDM_CONF" > /dev/null
        fi
    else
        sudo mkdir -p "$SDDM_CONF_D"
        echo -e "[Theme]\nCurrent=breeze" | sudo tee "$SDDM_CONF_D/10-theme.conf" > /dev/null
    fi
fi

# --- 7. Workspace Directory Layout Hierarchy Setup ---
log_info "Reviewing local system dotfile architecture layouts..."
CONFIG_DIRS=(
    "$HOME/.config/sway"
    "$HOME/.config/waybar"
    "$HOME/.config/mako"
    "$HOME/.config/foot"
    "$HOME/.config/alacritty"
    "$HOME/.local/bin"
)

for dir in "${CONFIG_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_success "Directory layout validated: $dir"
    else
        if [ "$DRY_RUN" = true ]; then
            log_warn "[Dry-Run] Missing dotfiles target path: $dir will be built."
        else
            log_info "Generating configuration structural folder: $dir"
            mkdir -p "$dir"
        fi
    fi
done

# --- 8. PipeWire System Configuration Symlinks ---
# Enables WirePlumber and pipewire-pulse system-wide config, same as
# install notes section 7.4 (source files live under /usr/share/examples).
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

# --- 9. PipeWire User Autostart (runit has no user-services) ---
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

# --- 10. zram Sysctl Tuning ---
# vm.swappiness=100 tells the kernel to use swap aggressively. With zram in
# RAM (priority 32767) that means we lean on compressed memory before any
# disk swap (install notes 13).
log_info "Reviewing zram sysctl tuning..."
ZRAM_SYSCTL="/etc/sysctl.d/99-zram.conf"
ZRAM_SYSCTL_LINE="vm.swappiness=100"

if [ -f "$ZRAM_SYSCTL" ] && grep -qx "$ZRAM_SYSCTL_LINE" "$ZRAM_SYSCTL"; then
    log_success "zram sysctl already in place: $ZRAM_SYSCTL"
else
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Will write $ZRAM_SYSCTL with '$ZRAM_SYSCTL_LINE'."
    else
        # /etc/sysctl.d/ is not pre-created on a base Void install; tee needs it.
        sudo mkdir -p "$(dirname "$ZRAM_SYSCTL")"
        echo "$ZRAM_SYSCTL_LINE" | sudo tee "$ZRAM_SYSCTL" > /dev/null
        sudo sysctl --system > /dev/null
        log_success "Wrote $ZRAM_SYSCTL and reloaded sysctl."
    fi
fi

# --- 11. Stale Package Cleanup ---
# Once NetworkManager is supervised, dhcpcd is redundant — NM ships its own
# DHCP client. We only remove the package when (a) it is installed,
# (b) its runit service has been unlinked (section 3 ran), and
# (c) NetworkManager is supervised so the box does not lose DHCP.
# wpa_supplicant the package is kept; NM uses it under the hood for WPA.
log_info "Reviewing stale packages..."
if ! xbps-query dhcpcd > /dev/null 2>&1; then
    log_success "dhcpcd package already absent."
elif [ -L "/var/service/dhcpcd" ]; then
    log_warn "dhcpcd still has an active runit symlink — leaving package alone."
elif [ ! -L "/var/service/NetworkManager" ]; then
    log_warn "NetworkManager not supervised yet — leaving dhcpcd in place as a safety net."
elif xbps-query base-system > /dev/null 2>&1; then
    # On a stock Void install, base-system declares dhcpcd as a hard
    # dependency, so xbps refuses to remove it. Swapping base-system for
    # base-files is the documented workaround, but it touches the base meta
    # so we leave that as a manual decision.
    log_warn "Cannot remove dhcpcd while the 'base-system' meta-package is installed."
    log_warn "  Manual workaround (destructive — review first):"
    log_warn "    sudo xbps-install -Sy base-files && sudo xbps-remove -y base-system && sudo xbps-remove -y dhcpcd"
    log_warn "  Or leave it: the disabled runit service consumes no resources at runtime."
elif [ "$DRY_RUN" = true ]; then
    log_warn "[Dry-Run] dhcpcd package will be removed (NM is supervising the network)."
else
    log_info "Removing redundant dhcpcd package..."
    sudo xbps-remove -y dhcpcd
fi

# --- 12. Qt Platform Theme env ---
# Set QT_QPA_PLATFORMTHEME=qt6ct in /etc/environment so any Qt6 app
# (pcmanfm-qt, future apps) picks up the centralized config from qt6ct:
# icon theme, widget style, color scheme. Has to live in /etc/environment
# (not ~/.zshrc) so PAM/elogind exports it BEFORE sway starts — apps
# spawned from sway don't source the user's shell rc. Without this, Qt
# apps render without toolbar icons and use the default Fusion palette.
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

log_success "=== VALIDATION / CORE DEPLOYMENT COMPLETE ==="
if [ "$DRY_RUN" = false ]; then
    log_info "Next: run ./setup-dotfiles.sh to write user-level configs."
fi
