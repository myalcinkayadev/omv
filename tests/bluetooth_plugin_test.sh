#!/usr/bin/env bash
# Behavior of the bar's Bluetooth item: the icon shows whether Bluetooth is on, and a click
# opens the Bluetooth card. blueutil is a stub.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/bluetooth.sh

# blueutil --power prints 1 or 0.
stub_blueutil() {
  cat > "$STUB_DIR/blueutil" <<STUB
#!/bin/sh
echo "blueutil \$*" >> "$CALL_LOG"
[ "\$1" = --power ] && echo $1
exit 0
STUB
  chmod +x "$STUB_DIR/blueutil"
}

# BLUEUTIL points at the stub, or at nothing, so a blueutil installed on this Mac never counts.
run_plugin() {
  local blueutil=$SANDBOX/missing-blueutil
  [ -x "$STUB_DIR/blueutil" ] && blueutil=$STUB_DIR/blueutil
  run_in_sandbox NAME=bluetooth BLUEUTIL="$blueutil" "$@" "$PLUGIN"
}

shows_on_icon() {
  stub_blueutil 1
  run_plugin SENDER=routine
  assert_called "^sketchybar --set bluetooth drawing=on icon=$(printf '\363\260\202\257')$"
}

shows_off_icon() {
  stub_blueutil 0
  run_plugin SENDER=routine
  assert_called "^sketchybar --set bluetooth drawing=on icon=$(printf '\363\260\202\262')$"
}

hides_without_blueutil() {
  run_plugin SENDER=routine
  assert_called '^sketchybar --set bluetooth drawing=off$'
}

opens_card_on_click() {
  stub hs
  run_plugin SENDER=mouse.clicked
  assert_called '^hs -c omvToggleBluetooth\(\)$'
}

run_case 'should show the on icon while Bluetooth is on' shows_on_icon
run_case 'should show the off icon while Bluetooth is off' shows_off_icon
run_case "should hide the item when blueutil isn't installed" hides_without_blueutil
run_case 'should open the Bluetooth card on a click' opens_card_on_click
finish
