#!/usr/bin/env bash
# Behavior of the SketchyBar starter, which AeroSpace and omv doctor --fix run, against stubs.

source "$(dirname "$0")/lib.sh"

readonly START=$REPO_DIR/config/sketchybar/.config/sketchybar/start.sh

# A bar that keeps running, as a real one would, until the test lets it go by creating
# $SANDBOX/release, so a second start meets it however slowly either start is launched.
held_bar() {
  printf '#!/bin/sh\necho sketchybar >> "%s"\nuntil [ -e "%s" ]; do sleep 0.05; done\n' \
    "$CALL_LOG" "$SANDBOX/release" > "$STUB_DIR/sketchybar"
  chmod +x "$STUB_DIR/sketchybar"
}

# A loaded Mac can hold a new process for many seconds before it runs, so the wait allows 60.
# It returns non-zero when the time runs out; the caller lets the bar go before failing.
wait_for() {
  local waited=0
  until eval "$1"; do
    [ "$waited" -lt 1200 ] || return 1
    sleep 0.05
    waited=$((waited + 1))
  done
}

starts_a_bar_when_none_runs() {
  held_bar
  touch "$SANDBOX/release"
  stub pgrep 1
  run_in_sandbox TMPDIR="$SANDBOX" "$START"
  assert_called '^sketchybar$'
}

leaves_a_running_bar_alone() {
  held_bar
  stub pgrep 0
  run_in_sandbox TMPDIR="$SANDBOX" "$START"
  assert_not_called '^sketchybar$'
}

# Whichever start loses the race returns while the other's bar still runs; then the bar is
# let go and the bars counted.
starts_one_bar_when_started_twice_at_once() {
  held_bar
  stub pgrep 1
  run_in_sandbox TMPDIR="$SANDBOX" "$START" &
  local first=$!
  run_in_sandbox TMPDIR="$SANDBOX" "$START" &
  local second=$!
  wait_for "! kill -0 $first 2>/dev/null || ! kill -0 $second 2>/dev/null" || true
  touch "$SANDBOX/release"
  wait
  [ "$(grep -c '^sketchybar$' "$CALL_LOG")" = 1 ] || fail "bars started: $(grep -c '^sketchybar$' "$CALL_LOG")"
}

succeeds_when_a_start_is_under_way() {
  held_bar
  stub pgrep 1
  run_in_sandbox TMPDIR="$SANDBOX" "$START" &
  wait_for "grep -q '^sketchybar$' '$CALL_LOG'" || { touch "$SANDBOX/release"; fail 'the first start never ran'; }
  run_in_sandbox TMPDIR="$SANDBOX" "$START" &
  local second=$!
  local returned=0
  wait_for "! kill -0 $second 2>/dev/null" || returned=1
  touch "$SANDBOX/release"
  local status=0
  wait "$second" || status=$?
  wait
  [ "$returned" = 0 ] || fail 'the second start waited for the first bar'
  [ "$status" = 0 ] || fail "the second start exited $status"
}

run_case 'should start a bar when none is running' starts_a_bar_when_none_runs
run_case 'should leave a running bar alone' leaves_a_running_bar_alone
run_case 'should start one bar when started twice at once' starts_one_bar_when_started_twice_at_once
run_case 'should succeed when a second start finds the first under way' succeeds_when_a_start_is_under_way
finish
