#!/bin/sh
# Shows the free space on the startup disk only while it's low: under 20 GB, or under 10%
# of a disk so large that 20 GB is little. A click opens the Disk card.
# df counts space macOS could purge as used, so the card, which asks Mole, can show more.

if [ "${SENDER:-}" = mouse.clicked ]; then
  hs -c 'omvToggleDisk()'
  exit 0
fi

# "<total KiB> <available KiB>" for /, nothing when df fails.
sizes=$(df -k / 2>/dev/null | awk 'NR == 2 { print $2, $4 }')

if [ -z "$sizes" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

label=$(printf '%s\n' "$sizes" | awk '{
  free = $2 * 1024; total = $1 * 1024; low = 20e9
  if (total / 10 > low) low = total / 10
  if (free < low) printf "%d GB", free / 1e9 + 0.5
}')

if [ -z "$label" ]; then
  sketchybar --set "$NAME" drawing=off
else
  sketchybar --set "$NAME" drawing=on label="$label"
fi
sketchybar --trigger bar_fit
