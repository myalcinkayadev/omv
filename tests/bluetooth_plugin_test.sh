#!/usr/bin/env bash
# Behavior of the bar's Bluetooth item: a click opens the Bluetooth card; Hammerspoon sets
# the icon. hs is a stub.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/config/sketchybar/.config/sketchybar/plugins/bluetooth.sh

opens_card_on_click() {
  stub hs
  run_in_sandbox NAME=bluetooth SENDER=mouse.clicked "$PLUGIN"
  assert_called '^hs -c omvToggleBluetooth\(\)$'
}

# The icon is Hammerspoon's to set, so the bar never waits on an hs call for it.
asks_nothing_otherwise() {
  stub hs
  run_in_sandbox NAME=bluetooth SENDER=system_woke "$PLUGIN"
  assert_not_called '^hs '
}

run_case 'should open the Bluetooth card on a click' opens_card_on_click
run_case 'should call no hs when the event is not a click' asks_nothing_otherwise
finish
