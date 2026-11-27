#!/bin/sh
# Opens the Bluetooth card on a click. The icon itself is set by Hammerspoon: macOS lets only
# apps given Bluetooth access read it, and Hammerspoon is the one given it, not SketchyBar.

PATH="$PATH:/opt/homebrew/bin"

[ "${SENDER:-}" = mouse.clicked ] && "${0%/*}/../hs.sh" 'omvToggleBluetooth()'
exit 0
