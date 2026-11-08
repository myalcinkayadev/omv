#!/usr/bin/env bash
# Behavior of the bar's volume item: clicks and the Sound menu.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/volume.sh

click() {
  stub hs
  run_in_sandbox NAME=volume SENDER=mouse.clicked BUTTON="$1" "$PLUGIN"
}

opens_sound_menu_on_right_click() {
  click right
  assert_called "^hs -c omvToggleSound\(\)$"
}

leaves_mute_alone_on_right_click() {
  click right
  assert_not_called '^osascript'
}

mutes_on_left_click() {
  click left
  assert_called '^osascript -e set volume output muted'
  assert_not_called '^hs '
}

run_case "should open the Sound menu on a right click" opens_sound_menu_on_right_click
run_case "should leave mute alone on a right click" leaves_mute_alone_on_right_click
run_case "should mute or unmute on a left click" mutes_on_left_click
finish
