#!/bin/sh
# Screen rotation for ThinkPad X61 Tablet under X11.
# Triggered by the bezel button (XF86RotateWindows) or Mod+Shift+R.
#
# Cycles: normal → right → inverted → left → normal
#
# After rotating the display with xrandr, the Wacom digitizer input
# coordinate system must be updated via xinput's Coordinate Transformation
# Matrix property so that pen/touch events map to the correct screen region.
#
# If your Wacom device name differs from the default below, set the
# WACOM_DEVICE env var before calling this script, or edit it here.
# Find the correct name with: xinput list | grep -i wacom

OUTPUT="LVDS-1"
STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/x11-screen-rotation"
# The X61 serial digitizer reports as "Wacom Serial Penabled Pen"; matching the
# broad "Wacom" substring covers its pen/eraser subdevices and firmware variants.
WACOM_DEVICE="${WACOM_DEVICE:-Wacom}"

# Coordinate transformation matrices for each rotation.
# These are 3x3 row-major affine matrices mapping device coords → screen coords.
# Format: "a b c d e f 0 0 1" where the 2D transform is [[a,b,c],[d,e,f]].
MATRIX_NORMAL="1 0 0 0 1 0 0 0 1"
MATRIX_RIGHT="0 1 0 -1 0 1 0 0 1"
MATRIX_INVERTED="-1 0 1 0 -1 1 0 0 1"
MATRIX_LEFT="0 -1 1 1 0 0 0 0 1"

current=$(cat "$STATE_FILE" 2>/dev/null || echo "normal")

case "$current" in
    normal)   next="right";    matrix="$MATRIX_RIGHT"    ;;
    right)    next="inverted"; matrix="$MATRIX_INVERTED" ;;
    inverted) next="left";     matrix="$MATRIX_LEFT"     ;;
    *)        next="normal";   matrix="$MATRIX_NORMAL"   ;;
esac

xrandr --output "$OUTPUT" --rotate "$next"
echo "$next" > "$STATE_FILE"

# Update all Wacom subdevices (Pen stylus, Pen eraser, Touch if present).
# xinput set-prop requires the exact property name as reported by the driver.
wacom_devices=$(xinput list --name-only 2>/dev/null | grep -i "$WACOM_DEVICE" || true)
if [ -z "$wacom_devices" ]; then
    echo "rotate_screen_x11: no Wacom device matching '$WACOM_DEVICE' found." >&2
    echo "  Set WACOM_DEVICE or verify with: xinput list | grep -i wacom" >&2
    exit 0
fi

echo "$wacom_devices" | while IFS= read -r dev; do
    xinput set-prop "$dev" "Coordinate Transformation Matrix" $matrix 2>/dev/null || true
done
