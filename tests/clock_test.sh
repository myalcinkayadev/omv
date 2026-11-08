#!/usr/bin/env bash
# Behavior of the bar's clock.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/clock.sh

# date prints a fixed time, so the label never depends on when the test runs.
stub_date() {
  cat > "$STUB_DIR/date" <<STUB
#!/bin/sh
echo "date \$*" >> "$CALL_LOG"
echo 'Sun Nov 8 12:09'
STUB
  chmod +x "$STUB_DIR/date"
}

asks_for_mac_format() {
  stub_date
  run_in_sandbox NAME=clock "$PLUGIN"
  assert_called '^date \+%a %b %-d %H:%M$'
}

shows_date_and_time() {
  stub_date
  run_in_sandbox NAME=clock "$PLUGIN"
  assert_called '^sketchybar --set clock label=Sun Nov 8 12:09$'
}

run_case 'should ask for the date like the macOS menu bar' asks_for_mac_format
run_case 'should show the weekday, month, day and time' shows_date_and_time
finish
