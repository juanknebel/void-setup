#!/bin/sh
# Breeze Dark — palette consistent with alacritty.toml.
# Use printf instead of `echo -e` because /bin/sh on Void is dash, and dash
# does not recognize -e: it prints it literally as the first menu option.
SELECTION=$(printf '🔒 Lock\n🔄 Reboot\n🛑 Shutdown\n🚪 Logout\n' | fuzzel --dmenu --background-color=232629ff --text-color=eff0f1ff --match-color=3daee9ff --selection-color=31363bff --selection-text-color=eff0f1ff --border-color=3daee9ff --border-width=2 -p "System: ")

case "$SELECTION" in
    "🔒 Lock") swaylock -c 232629 --ring-color 3daee9 --inside-color 31363b --text-color eff0f1 ;;
    "🔄 Reboot") loginctl reboot ;;
    "🛑 Shutdown") loginctl poweroff ;;
    "🚪 Logout") swaymsg exit ;;
esac
