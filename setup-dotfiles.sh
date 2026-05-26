#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR/dotfiles"
IMAGES_DIR="$SCRIPT_DIR/images"

DRY_RUN=false

log_info()    { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
log_warn()    { echo -e "\033[0;33m[WARN]\033[0m $1"; }
log_err()     { echo -e "\033[0;31m[ERROR]\033[0m $1" >&2; }

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -d, --dry-run    Show what would be written/backed up without modifying any file."
    echo "  -h, --help       Show this help message."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run) DRY_RUN=true; shift ;;
        -h|--help)    show_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    log_warn "=== RUNNING IN DRY-RUN MODE (NO FILES WILL BE WRITTEN) ==="
fi

# Save a .bak.<timestamp> copy of a regular file before overwriting it.
# Symlinks and missing files are silently skipped (set -e safe).
# In dry-run, only reports what would happen.
backup_if_exists() {
    if [ -f "$1" ] && [ ! -L "$1" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_warn "[Dry-Run] Would back up: $1 -> $1.bak.<timestamp>"
        else
            local ts dest
            ts=$(date +%Y%m%d%H%M%S)
            dest="$1.bak.$ts"
            cp -a "$1" "$dest"
            log_info "Backup: $1 -> $dest"
        fi
    fi
}

# Copy a payload file to its destination, honoring dry-run and backup
# conventions. Source mode (incl. executable bit) is preserved. The src
# path is absolute; callers usually build it from $DOTFILES_DIR or $IMAGES_DIR.
install_file() {
    local src="$1"
    local dest="$2"
    if [ ! -f "$src" ]; then
        log_err "Missing payload file: $src"
        exit 1
    fi
    backup_if_exists "$dest"
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Would copy: $src -> $dest"
    else
        cp -p -- "$src" "$dest"
        log_info "Installed: $dest"
    fi
}

# Create dirs idempotently; dry-run only logs the would-create dirs.
ensure_dir() {
    for d in "$@"; do
        [ -d "$d" ] && continue
        if [ "$DRY_RUN" = true ]; then
            log_warn "[Dry-Run] Would create dir: $d"
        else
            mkdir -p "$d"
        fi
    done
}

# chmod +x respecting dry-run.
ensure_executable() {
    if [ "$DRY_RUN" = true ]; then
        log_warn "[Dry-Run] Would chmod +x: $*"
    else
        chmod +x "$@"
    fi
}

log_info "Installing local Breeze Dark configurations from $DOTFILES_DIR..."

# Ensure target dirs exist (setup-system.sh also creates most of these, but
# this script must be runnable on its own).
ensure_dir ~/.config/sway ~/.config/waybar ~/.config/mako ~/.config/foot ~/.config/alacritty ~/.local/bin ~/Pictures

# --- 1. Sway ---
install_file "$DOTFILES_DIR/sway/config" ~/.config/sway/config
log_success "Sway core configuration installed."

# --- 2. Waybar ---
install_file "$DOTFILES_DIR/waybar/config"    ~/.config/waybar/config
install_file "$DOTFILES_DIR/waybar/style.css" ~/.config/waybar/style.css
log_success "Waybar config and layout styling installed."

# --- 3. Mako & Foot ---
install_file "$DOTFILES_DIR/mako/config"   ~/.config/mako/config
install_file "$DOTFILES_DIR/foot/foot.ini" ~/.config/foot/foot.ini
log_success "Mako and Foot desktop interfaces installed."

# --- 4. Automation scripts ---
install_file "$DOTFILES_DIR/local/bin/rotate_screen_twm.sh" ~/.local/bin/rotate_screen_twm.sh
install_file "$DOTFILES_DIR/local/bin/powermenu.sh"         ~/.local/bin/powermenu.sh
ensure_executable ~/.local/bin/rotate_screen_twm.sh ~/.local/bin/powermenu.sh
log_success "Tablet rotation engine and safe power configurations installed."

# --- 5. Shell environment (zsh + Starship) ---
# chsh is intentionally NOT performed — the system shell stays bash, and
# Alacritty/foot launch zsh on their own.
install_file "$DOTFILES_DIR/zshrc"         ~/.zshrc
install_file "$DOTFILES_DIR/starship.toml" ~/.config/starship.toml
log_success "Shell environment (zsh + Starship) installed."

# --- 6. Alacritty ---
install_file "$DOTFILES_DIR/alacritty/alacritty.toml" ~/.config/alacritty/alacritty.toml
log_success "Alacritty terminal configuration installed."

# --- 7. Wallpapers (sway picks them up via swaybg in its config) ---
install_file "$IMAGES_DIR/forest_2560x1600.jpg" ~/Pictures/forest_2560x1600.jpg
log_success "Wallpapers installed to ~/Pictures."
