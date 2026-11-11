#!/usr/bin/env bash
# Behavior of the bar item that keeps the Mac awake.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/keep_awake.sh

pid_file() {
  echo "$HOME_DIR/.local/state/omv/keep-awake.pid"
}

# The pgrep stub decides whether the saved caffeinate is running: exit 0 means it is.
simulate_on() {
  mkdir -p "$(dirname "$(pid_file)")"
  echo 4242 > "$(pid_file)"
}

simulate_off() {
  stub pgrep 1
}

# caffeinate runs in the background, so its call can land just after the plugin exits.
# It waits up to 5 seconds, since tests/run.sh runs every file at once and can slow it down.
assert_eventually_called() {
  local attempt
  for attempt in $(seq 50); do
    grep -qE -e "$1" "$CALL_LOG" && return 0
    sleep 0.1
  done
  fail "expected a call matching: $1"$'\n'"$(cat "$CALL_LOG")"
}

toggle() {
  run_in_sandbox NAME=keep_awake SENDER="${1:-keep_awake_toggle}" "$PLUGIN"
}

starts_caffeinate_when_off() {
  simulate_off
  stub caffeinate
  toggle
  assert_eventually_called '^caffeinate -di$'
}

saves_pid_when_started() {
  simulate_off
  stub caffeinate
  toggle
  [ -s "$(pid_file)" ] || fail 'no pid file was saved'
}

shows_icon_when_turned_on() {
  simulate_off
  stub caffeinate
  toggle
  assert_called '^sketchybar --set keep_awake drawing=on$'
}

stops_caffeinate_when_on() {
  simulate_on
  toggle
  assert_called "^pkill -F $(pid_file) -x caffeinate$"
}

removes_pid_when_stopped() {
  simulate_on
  toggle
  if [ -e "$(pid_file)" ]; then
    fail 'pid file was kept'
  fi
}

hides_icon_when_turned_off() {
  simulate_on
  toggle
  assert_called '^sketchybar --set keep_awake drawing=off$'
}

toggles_when_clicked() {
  simulate_on
  toggle mouse.clicked
  assert_called '^pkill '
}

shows_icon_when_on_without_toggle() {
  simulate_on
  run_in_sandbox NAME=keep_awake SENDER=forced "$PLUGIN"
  assert_called '^sketchybar --set keep_awake drawing=on$'
}

changes_nothing_without_toggle() {
  simulate_on
  stub caffeinate
  run_in_sandbox NAME=keep_awake SENDER=forced "$PLUGIN"
  assert_not_called '^(pkill|caffeinate)'
}

hides_icon_when_saved_pid_is_dead() {
  simulate_on
  simulate_off
  run_in_sandbox NAME=keep_awake SENDER=forced "$PLUGIN"
  assert_called '^sketchybar --set keep_awake drawing=off$'
}

run_case 'should start caffeinate -di when toggled while off' starts_caffeinate_when_off
run_case 'should save the caffeinate pid when it starts' saves_pid_when_started
run_case 'should show the icon when it turns on' shows_icon_when_turned_on
run_case 'should stop the saved caffeinate when toggled while on' stops_caffeinate_when_on
run_case 'should remove the pid file when it stops' removes_pid_when_stopped
run_case 'should hide the icon when it turns off' hides_icon_when_turned_off
run_case 'should toggle when the icon is clicked' toggles_when_clicked
run_case 'should show the icon when on and not toggled' shows_icon_when_on_without_toggle
run_case 'should start or stop nothing when not toggled' changes_nothing_without_toggle
run_case 'should hide the icon when the saved caffeinate is not running' hides_icon_when_saved_pid_is_dead
finish
