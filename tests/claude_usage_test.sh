#!/usr/bin/env bash
# Behavior of the bar's Claude usage limit: the writer, the bar plugin and the wrapper line.

source "$(dirname "$0")/lib.sh"

readonly WRITER=$REPO_DIR/claude/.claude/bar-usage.sh
readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/claude_usage.sh
readonly LINK=$REPO_DIR/claude-usage.sh

# Far from any run of these tests, so nothing depends on today's date.
readonly FUTURE=4102444800
readonly PAST=1577836800

state_file() {
  echo "$HOME_DIR/.local/state/omv/claude-usage"
}

wrapper() {
  echo "$HOME_DIR/.claude/statusline-wrapper.sh"
}

status_json() {
  printf '{"session_id":"secret-session","cwd":"/secret/path","rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' "$1" "$2" "$3" "$4"
}

save_usage() {
  mkdir -p "$(dirname "$(state_file)")"
  printf '%s %s %s %s\n' "$1" "$2" "$3" "$4" > "$(state_file)"
}

run_plugin() {
  run_in_sandbox NAME=claude_usage "$@" "$PLUGIN"
}

write_wrapper() {
  mkdir -p "$HOME_DIR/.claude"
  printf '#!/bin/bash\n\n# Read JSON input once\ninput=$(cat)\n\necho "$input" | other-command\n' > "$(wrapper)"
}

saves_both_windows() {
  status_json 23.5 100 41.2 200 | run_in_sandbox "$WRITER"
  [ "$(cat "$(state_file)")" = '23.5 100 41.2 200' ] || fail "saved: $(cat "$(state_file)")"
}

keeps_values_without_rate_limits() {
  save_usage 10 100 20 200
  printf '{"session_id":"s1"}' | run_in_sandbox "$WRITER"
  [ "$(cat "$(state_file)")" = '10 100 20 200' ] || fail "saved: $(cat "$(state_file)")"
}

stores_nothing_else() {
  status_json 23.5 100 41.2 200 | run_in_sandbox "$WRITER"
  if grep -q 'secret' "$(state_file)"; then
    fail 'stored session data'
  fi
}

survives_invalid_json() {
  printf 'not json' | assert_exit_zero run_in_sandbox "$WRITER"
}

survives_missing_sketchybar() {
  stub sketchybar 127
  status_json 1 2 3 4 | assert_exit_zero run_in_sandbox "$WRITER"
}

notifies_when_changed() {
  status_json 1 2 3 4 | run_in_sandbox "$WRITER"
  assert_called '^sketchybar --trigger claude_usage_change$'
}

skips_notify_when_unchanged() {
  save_usage 1 2 3 4
  status_json 1 2 3 4 | run_in_sandbox "$WRITER"
  assert_not_called '^sketchybar'
}

shows_both_windows() {
  save_usage 23 "$FUTURE" 41 "$FUTURE"
  run_plugin
  assert_called 'label=5h 23%  7d 41% '
}

rounds_percentages() {
  save_usage 23.5 "$FUTURE" 41.2 "$FUTURE"
  run_plugin
  assert_called 'label=5h 24%  7d 41% '
}

zeroes_passed_window() {
  save_usage 90 "$PAST" 41 "$FUTURE"
  run_plugin
  assert_called 'label=5h 0%  7d 41% '
}

gray_under_70() {
  save_usage 69 "$FUTURE" 10 "$FUTURE"
  run_plugin
  assert_called 'label.color=0xff7a7a7a background.drawing=off$'
}

white_at_70() {
  save_usage 70 "$FUTURE" 10 "$FUTURE"
  run_plugin
  assert_called 'label.color=0xffffffff background.drawing=off$'
}

pill_at_90() {
  save_usage 90 "$FUTURE" 10 "$FUTURE"
  run_plugin
  assert_called 'label.color=0xff000000 background.drawing=on$'
}

uses_higher_window() {
  save_usage 10 "$FUTURE" 95 "$FUTURE"
  run_plugin
  assert_called 'label.color=0xff000000 background.drawing=on$'
}

shows_resets_after_click() {
  save_usage 23 "$FUTURE" 41 "$FUTURE"
  run_plugin SENDER=mouse.clicked
  local five seven
  five=$(date -r "$FUTURE" '+%H:%M')
  seven=$(date -r "$FUTURE" '+%a %H:%M')
  assert_called "label=5h $five  7d $seven "
}

shows_percentages_after_second_click() {
  save_usage 23 "$FUTURE" 41 "$FUTURE"
  run_plugin SENDER=mouse.clicked
  : > "$CALL_LOG"
  run_plugin SENDER=mouse.clicked
  assert_called 'label=5h 23%  7d 41% '
}

hides_without_data() {
  run_plugin
  assert_called '^sketchybar --set claude_usage drawing=off$'
}

adds_line() {
  write_wrapper
  run_in_sandbox "$LINK" add
  grep -q 'bar-usage.sh' "$(wrapper)" || fail "$(cat "$(wrapper)")"
}

adds_line_after_input_is_read() {
  write_wrapper
  run_in_sandbox "$LINK" add
  [ "$(grep -n 'input=$(cat)' "$(wrapper)" | cut -d: -f1)" -lt "$(grep -n 'bar-usage.sh' "$(wrapper)" | cut -d: -f1)" ] || fail "$(cat "$(wrapper)")"
}

adds_nothing_twice() {
  write_wrapper
  run_in_sandbox "$LINK" add
  run_in_sandbox "$LINK" add
  [ "$(grep -c 'bar-usage.sh' "$(wrapper)")" = 1 ] || fail "$(cat "$(wrapper)")"
}

keeps_rest_of_wrapper() {
  write_wrapper
  local before
  before=$(cat "$(wrapper)")
  run_in_sandbox "$LINK" add
  [ "$(grep -v 'bar-usage.sh' "$(wrapper)")" = "$before" ] || fail "$(cat "$(wrapper)")"
}

keeps_wrapper_executable() {
  write_wrapper
  chmod 755 "$(wrapper)"
  run_in_sandbox "$LINK" add
  [ -x "$(wrapper)" ] || fail 'wrapper lost its executable bit'
}

ignores_missing_wrapper() {
  run_in_sandbox "$LINK" add >/dev/null
  [ ! -e "$(wrapper)" ] || fail 'wrapper was created'
}

leaves_unknown_wrapper_unchanged() {
  mkdir -p "$HOME_DIR/.claude"
  echo 'echo custom' > "$(wrapper)"
  run_in_sandbox "$LINK" add >/dev/null
  [ "$(cat "$(wrapper)")" = 'echo custom' ] || fail "$(cat "$(wrapper)")"
}

removes_only_its_line() {
  write_wrapper
  local before
  before=$(cat "$(wrapper)")
  run_in_sandbox "$LINK" add
  run_in_sandbox "$LINK" remove
  [ "$(cat "$(wrapper)")" = "$before" ] || fail "$(cat "$(wrapper)")"
}

run_case 'should save both percentages and reset times when rate_limits is present' saves_both_windows
run_case 'should keep the last values when rate_limits is absent' keeps_values_without_rate_limits
run_case 'should store nothing else from the input' stores_nothing_else
run_case 'should exit zero when the input is invalid JSON' survives_invalid_json
run_case 'should exit zero when sketchybar is missing' survives_missing_sketchybar
run_case 'should notify the bar when the values change' notifies_when_changed
run_case 'should not notify the bar when the values are unchanged' skips_notify_when_unchanged
run_case 'should show both windows when data exists' shows_both_windows
run_case 'should round percentages to whole numbers' rounds_percentages
run_case 'should show 0% for a window whose reset time has passed' zeroes_passed_window
run_case 'should use gray when usage is under 70%' gray_under_70
run_case 'should use white when usage is 70%' white_at_70
run_case 'should use the pill when usage is 90%' pill_at_90
run_case 'should use the higher window for the color' uses_higher_window
run_case 'should show reset times after a click' shows_resets_after_click
run_case 'should show percentages after a second click' shows_percentages_after_second_click
run_case 'should hide the item when no data exists' hides_without_data
run_case 'should add the line when it is missing' adds_line
run_case 'should add the line after the input is read' adds_line_after_input_is_read
run_case 'should add nothing when run twice' adds_nothing_twice
run_case 'should keep the rest of the wrapper unchanged' keeps_rest_of_wrapper
run_case 'should keep the wrapper executable' keeps_wrapper_executable
run_case 'should do nothing when the wrapper does not exist' ignores_missing_wrapper
run_case 'should leave a wrapper unchanged when it does not read input the expected way' leaves_unknown_wrapper_unchanged
run_case 'should remove only its own line when uninstalling' removes_only_its_line
finish
