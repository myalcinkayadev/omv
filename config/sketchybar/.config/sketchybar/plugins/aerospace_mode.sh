#!/bin/sh
# Shows the AeroSpace binding mode, so resize mode is never invisible.

mode=${MODE:-main}

if [ "$mode" = main ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

sketchybar --set "$NAME" drawing=on label="$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')"
