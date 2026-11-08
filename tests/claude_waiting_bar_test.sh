#!/usr/bin/env bash
# Behavior of the bar item that shows Claude Code sessions waiting for you.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/claude_waiting.sh
# No process has this PID, so a session saved with it counts as ended.
readonly DEAD_PID=999999

state_dir() {
  echo "$HOME_DIR/.local/state/omv/claude-waiting"
}

# A waiting session: name, Claude's PID, folder and when it started waiting.
save_session() {
  mkdir -p "$(state_dir)"
  printf '%s\t/dev/ttys009\t%s\t%s\n' "$2" "$3" "$4" > "$(state_dir)/$1"
}

run_plugin() {
  run_in_sandbox NAME=claude_waiting "$@" "$PLUGIN"
}

shows_the_folder() {
  save_session one $$ omv 100
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=on label=waiting · omv$'
}

shows_the_oldest_and_a_count() {
  save_session one $$ api 200
  save_session two $$ omv 100
  run_plugin
  assert_called 'label=waiting · omv \+1$'
}

hides_with_none() {
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=off'
}

skips_an_ended_session() {
  save_session one $DEAD_PID omv 100
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=off'
}

removes_an_ended_session() {
  save_session one $DEAD_PID omv 100
  run_plugin
  [ ! -e "$(state_dir)/one" ] || fail 'kept an ended session'
}

cuts_a_long_folder() {
  save_session one $$ a-very-long-folder-name 100
  run_plugin
  assert_called 'label=waiting · a-very-long…$'
}

checks_the_fit() {
  save_session one $$ omv 100
  run_plugin
  assert_called 'sketchybar --trigger bar_fit'
}

focuses_on_click() {
  stub hs
  run_plugin SENDER=mouse.clicked
  assert_called "hs -c omvFocusClaude\(\)"
}

run_case 'should show the folder when one session waits' shows_the_folder
run_case 'should show the oldest folder and +N when several wait' shows_the_oldest_and_a_count
run_case 'should hide the item when no session waits' hides_with_none
run_case 'should hide the item when the waiting Claude has ended' skips_an_ended_session
run_case 'should remove a session whose Claude has ended' removes_an_ended_session
run_case 'should cut a long folder name at 12 characters' cuts_a_long_folder
run_case 'should check the fit when the item changes' checks_the_fit
run_case 'should focus the waiting session on a click' focuses_on_click
finish
