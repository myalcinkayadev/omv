#!/usr/bin/env bash
# Behavior of the SketchyBar starter, which AeroSpace and omv doctor --fix run, against stubs.

source "$(dirname "$0")/lib.sh"

readonly START=$REPO_DIR/config/sketchybar/.config/sketchybar/start.sh

# A bar that keeps running for a moment, as a real one would, so a second start meets it.
slow_bar() {
  printf '#!/bin/sh\necho sketchybar >> "%s"\nsleep 1\n' "$CALL_LOG" > "$STUB_DIR/sketchybar"
  chmod +x "$STUB_DIR/sketchybar"
}

starts_a_bar_when_none_runs() {
  slow_bar
  stub pgrep 1
  run_in_sandbox TMPDIR="$SANDBOX" "$START"
  assert_called '^sketchybar$'
}

leaves_a_running_bar_alone() {
  slow_bar
  stub pgrep 0
  run_in_sandbox TMPDIR="$SANDBOX" "$START"
  assert_not_called '^sketchybar$'
}

starts_one_bar_when_started_twice_at_once() {
  slow_bar
  stub pgrep 1
  run_in_sandbox TMPDIR="$SANDBOX" "$START" &
  run_in_sandbox TMPDIR="$SANDBOX" "$START"
  wait
  [ "$(grep -c '^sketchybar$' "$CALL_LOG")" = 1 ] || fail "bars started: $(grep -c '^sketchybar$' "$CALL_LOG")"
}

run_case 'should start a bar when none is running' starts_a_bar_when_none_runs
run_case 'should leave a running bar alone' leaves_a_running_bar_alone
run_case 'should start one bar when started twice at once' starts_one_bar_when_started_twice_at_once
finish
