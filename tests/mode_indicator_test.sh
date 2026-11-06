#!/usr/bin/env bash
# Behavior of the bar item that shows the AeroSpace binding mode.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/aerospace_mode.sh

shows_resize() {
  run_in_sandbox NAME=mode MODE=resize "$PLUGIN"
  assert_called '^sketchybar --set mode drawing=on label=RESIZE$'
}

hides_on_main() {
  run_in_sandbox NAME=mode MODE=main "$PLUGIN"
  assert_called '^sketchybar --set mode drawing=off$'
}

hides_without_mode() {
  run_in_sandbox NAME=mode "$PLUGIN"
  assert_called '^sketchybar --set mode drawing=off$'
}

run_case 'should show RESIZE when the mode is resize' shows_resize
run_case 'should hide the indicator when the mode is main' hides_on_main
run_case 'should hide the indicator when no mode is given' hides_without_mode
finish
