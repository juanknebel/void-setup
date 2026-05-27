#!/bin/sh
# Cycles the X220 panel rotation through 4 orientations under Plasma/KWin.
# kscreen-doctor drives the display rotation; KWin auto-rotates mapped
# touch/tablet inputs with the output, so no extra input remap is needed
# (unlike the Sway version). State is kept in a file because kscreen-doctor
# has no "get current rotation" subcommand that's easy to parse.
# OUTPUT is hardcoded per the install notes (X220 = LVDS-1).
OUTPUT="LVDS-1"
STATE_FILE="$HOME/.cache/kde-screen-rotation"
mkdir -p "$(dirname "$STATE_FILE")"

CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "none")
case "$CURRENT" in
    none)     NEXT="right" ;;
    right)    NEXT="inverted" ;;
    inverted) NEXT="left" ;;
    *)        NEXT="none" ;;
esac

kscreen-doctor "output.${OUTPUT}.rotation.${NEXT}"
echo "$NEXT" > "$STATE_FILE"
