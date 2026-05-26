#!/bin/sh
# Cycles the X220 panel rotation through 4 orientations.
# Parsing wlr-randr/swaymsg without jq is fragile, so we keep the state
# in a file. OUTPUT is hardcoded per the install notes (X220 = eDP-1).
OUTPUT="LVDS-1"
STATE_FILE="$HOME/.cache/sway-screen-rotation"
mkdir -p "$(dirname "$STATE_FILE")"

CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "normal")
case "$CURRENT" in
    normal) NEXT="90" ;;
    90)     NEXT="180" ;;
    180)    NEXT="270" ;;
    *)      NEXT="normal" ;;
esac

swaymsg output "$OUTPUT" transform "$NEXT"
swaymsg input type:tablet_tool map_to_output "$OUTPUT"
swaymsg input type:touch       map_to_output "$OUTPUT"
echo "$NEXT" > "$STATE_FILE"
