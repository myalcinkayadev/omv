#!/bin/sh
# Draws the Bluetooth icon, on or off, and opens the Bluetooth card on a click. Hidden when
# blueutil, which reads Bluetooth's state, isn't installed.

PATH="$PATH:/opt/homebrew/bin"
blueutil=${BLUEUTIL:-blueutil}

if [ "${SENDER:-}" = mouse.clicked ]; then
  hs -c 'omvToggleBluetooth()'
  exit 0
fi

if ! command -v "$blueutil" >/dev/null 2>&1; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

if [ "$("$blueutil" --power 2>/dev/null)" = 1 ]; then
  glyph='\363\260\202\257'
else
  glyph='\363\260\202\262'
fi

sketchybar --set "$NAME" drawing=on icon="$(printf "$glyph")"
