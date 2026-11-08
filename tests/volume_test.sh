#!/usr/bin/env bash
# Behavior of the bar's volume item: clicks open the Sound card.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/volume.sh

click() {
  stub hs
  run_in_sandbox NAME=volume SENDER=mouse.clicked BUTTON="$1" "$PLUGIN"
}

opens_sound_card_on_left_click() {
  click left
  assert_called "^hs -c omvToggleSound\(\)$"
}

opens_sound_card_on_right_click() {
  click right
  assert_called "^hs -c omvToggleSound\(\)$"
}

leaves_mute_alone_on_click() {
  click left
  assert_not_called '^osascript'
}

run_case "should open the Sound card on a left click" opens_sound_card_on_left_click
run_case "should open the Sound card on a right click" opens_sound_card_on_right_click
run_case "should leave mute alone on a click" leaves_mute_alone_on_click
finish
