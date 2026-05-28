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
# conventions. Source mode (incl. executable bit) is preserved.
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

# Create dirs idempotently.
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

log_info "Installing Breeze Dark i3/X11 configurations from $DOTFILES_DIR..."

ensure_dir \
    ~/.config/i3 \
    ~/.config/polybar \
    ~/.config/dunst \
    ~/.config/picom \
    ~/.config/rofi \
    ~/.config/alacritty \
    ~/.local/bin \
    ~/Pictures

# --- 1. i3 ---
install_file "$DOTFILES_DIR/i3/config" ~/.config/i3/config
log_success "i3 core configuration installed."

# --- 2. Polybar ---
install_file "$DOTFILES_DIR/polybar/config.ini" ~/.config/polybar/config.ini
install_file "$DOTFILES_DIR/polybar/launch.sh"  ~/.config/polybar/launch.sh
ensure_executable ~/.config/polybar/launch.sh
log_success "Polybar config and launch script installed."

# --- 3. Dunst ---
install_file "$DOTFILES_DIR/dunst/dunstrc" ~/.config/dunst/dunstrc
log_success "Dunst notification config installed."

# --- 4. Picom ---
install_file "$DOTFILES_DIR/picom/picom.conf" ~/.config/picom/picom.conf
log_success "Picom compositor config installed."

# --- 5. Rofi ---
install_file "$DOTFILES_DIR/rofi/config.rasi" ~/.config/rofi/config.rasi
log_success "Rofi launcher config installed."

# --- 6. Automation scripts ---
install_file "$DOTFILES_DIR/local/bin/rotate_screen_x11.sh" ~/.local/bin/rotate_screen_x11.sh
install_file "$DOTFILES_DIR/local/bin/powermenu.sh"         ~/.local/bin/powermenu.sh
install_file "$DOTFILES_DIR/local/bin/lock.sh"              ~/.local/bin/lock.sh
ensure_executable \
    ~/.local/bin/rotate_screen_x11.sh \
    ~/.local/bin/powermenu.sh \
    ~/.local/bin/lock.sh
log_success "Tablet rotation, power menu, and lock scripts installed."

# --- 7. Shell environment (zsh + Starship) ---
# chsh is intentionally NOT performed — the system shell stays bash, and
# Alacritty launches zsh on its own.
install_file "$DOTFILES_DIR/zshrc"         ~/.zshrc
install_file "$DOTFILES_DIR/starship.toml" ~/.config/starship.toml
log_success "Shell environment (zsh + Starship) installed."

# --- 8. Alacritty ---
install_file "$DOTFILES_DIR/alacritty/alacritty.toml" ~/.config/alacritty/alacritty.toml
log_success "Alacritty terminal configuration installed."

# --- 9. X11 session files ---
install_file "$DOTFILES_DIR/Xresources" ~/.Xresources
install_file "$DOTFILES_DIR/xprofile"   ~/.xprofile
log_success "X11 session files (Xresources, xprofile) installed."

# --- 10. Wallpapers ---
install_file "$IMAGES_DIR/forest_2560x1600.jpg" ~/Pictures/forest_2560x1600.jpg
log_success "Wallpapers installed to ~/Pictures."
