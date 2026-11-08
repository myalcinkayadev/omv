#!/usr/bin/env bash
# Behavior of the bar's battery item: a click opens the Battery card.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/battery.sh

opens_battery_card_on_click() {
  stub hs
  run_in_sandbox NAME=battery SENDER=mouse.clicked "$PLUGIN"
  assert_called "^hs -c omvToggleBattery\(\)$"
}

leaves_card_closed_on_timer() {
  stub hs
  cat > "$STUB_DIR/pmset" <<'STUB'
#!/bin/sh
printf " -InternalBattery-0 (id=1)\t78%%; discharging; 6:05 remaining present: true\n"
STUB
  chmod +x "$STUB_DIR/pmset"
  run_in_sandbox NAME=battery SENDER=routine "$PLUGIN"
  assert_not_called '^hs '
}

run_case "should open the Battery card on a click" opens_battery_card_on_click
run_case "should leave the card closed when the timer redraws the icon" leaves_card_closed_on_timer
finish
