#!/bin/sh
# Draws the Bluetooth icon, on or off, and opens the Bluetooth card on a click. The state
# comes from Hammerspoon: macOS lets only apps given Bluetooth access read it, and
# Hammerspoon is the one given it, not SketchyBar. Hidden while Hammerspoon can't tell,
# for example before that access is given or without blueutil.

PATH="$PATH:/opt/homebrew/bin"

if [ "${SENDER:-}" = mouse.clicked ]; then
  hs -c 'omvToggleBluetooth()'
  exit 0
fi

# hs -c prints any extension Hammerspoon loads before the answer, so only the last line counts.
power=$(hs -c 'return omvBluetoothPower()' 2>/dev/null | tail -n 1)

case $power in
  1) glyph='\363\260\202\257' ;;
  0) glyph='\363\260\202\262' ;;
  *)
    sketchybar --set "$NAME" drawing=off
    exit 0
    ;;
esac

sketchybar --set "$NAME" drawing=on icon="$(printf "$glyph")"
