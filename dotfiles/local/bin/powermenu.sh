#!/bin/sh
# Power menu using rofi in dmenu mode.
# Icons are Nerd Font (Material Design Icons) — rofi must use JetBrainsMono
# Nerd Font so the glyphs render instead of tofu boxes.
# Use printf instead of `echo -e` because /bin/sh on Void is dash, and dash
# does not recognize -e: it prints it literally as the first menu option.
SELECTION=$(printf '󰌾 Lock\n󰜉 Reboot\n󰐥 Shutdown\n󰍃 Logout\n' | \
    rofi -dmenu \
         -p "Power:" \
         -font "JetBrainsMono Nerd Font 12" \
         -theme-str 'window {width: 260px;} listview {lines: 4;}')

case "$SELECTION" in
    "󰌾 Lock")     exec ~/.local/bin/lock.sh ;;
    "󰜉 Reboot")   exec loginctl reboot ;;
    "󰐥 Shutdown") exec loginctl poweroff ;;
    "󰍃 Logout")   exec i3-msg exit ;;
esac
