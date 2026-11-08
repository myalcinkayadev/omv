#!/usr/bin/env bash
# Behavior of the bar's Wi-Fi item: a click opens the Wi-Fi card.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/wifi.sh

opens_wifi_card_on_click() {
  stub hs
  run_in_sandbox NAME=wifi SENDER=mouse.clicked "$PLUGIN"
  assert_called "^hs -c omvToggleWifi\(\)$"
}

leaves_card_closed_on_timer() {
  stub hs
  stub ipconfig 1
  run_in_sandbox NAME=wifi SENDER=routine "$PLUGIN"
  assert_not_called '^hs '
}

run_case "should open the Wi-Fi card on a click" opens_wifi_card_on_click
run_case "should leave the card closed when the timer redraws the icon" leaves_card_closed_on_timer
finish
