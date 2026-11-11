#!/usr/bin/env bash
# Behavior of the bar item that shows Claude Code sessions waiting for you: asking for
# approval, or done and waiting for the next prompt. Working sessions stay out of it.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/claude_waiting.sh
# No process has this PID, so a session saved with it counts as ended.
readonly DEAD_PID=999999

state_dir() {
  echo "$HOME_DIR/.local/state/omv/claude-sessions"
}

# A session: name, Claude's PID, folder, when it entered its state, and the state (done
# unless given).
save_session() {
  mkdir -p "$(state_dir)"
  printf '%s\t/dev/ttys009\t%s\t%s\t%s\n' "$2" "$3" "$4" "${5:-done}" > "$(state_dir)/$1"
}

# A file written before states existed: four fields, no state.
save_old_session() {
  mkdir -p "$(state_dir)"
  printf '%s\t/dev/ttys009\t%s\t%s\n' "$2" "$3" "$4" > "$(state_dir)/$1"
}

run_plugin() {
  run_in_sandbox NAME=claude_waiting "$@" "$PLUGIN"
}

shows_the_folder() {
  save_session one $$ omv 100
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=on label=omv$'
}

shows_the_oldest_and_a_count() {
  save_session one $$ api 200
  save_session two $$ omv 100
  run_plugin
  assert_called 'label=omv \+1$'
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
  assert_called 'label=a-very-long…$'
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

hides_when_every_session_works() {
  save_session one $$ omv 100 working
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=off'
}

shows_asking_before_done() {
  save_session one $$ omv 100 done
  save_session two $$ api 200 asks
  run_plugin
  assert_called 'label=\? api \+1$'
}

marks_an_asking_session() {
  save_session one $$ omv 100 asks
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=on label=\? omv$'
}

counts_only_waiting_sessions() {
  save_session one $$ omv 100 done
  save_session two $$ api 50 working
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=on label=omv$'
}

reads_an_old_file_as_done() {
  save_old_session one $$ omv 100
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=on label=omv$'
}

# Hammerspoon marks a session seen at the moment its state began.
mark_seen() {
  printf '%s\n' "$2" > "$(state_dir)/.seen-$1"
}

hides_a_seen_session() {
  save_session one $$ omv 100 done
  mark_seen one 100
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=off'
}

shows_a_seen_session_after_a_change() {
  save_session one $$ omv 200 asks
  mark_seen one 100
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=on label=\? omv$'
}

ignores_a_seen_file_of_an_ended_session() {
  save_session one $$ omv 100 done
  mark_seen gone 100
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=on label=omv$'
}

reads_a_line_with_an_agent() {
  mkdir -p "$(state_dir)"
  printf '%s\t/dev/ttys009\tomv\t100\tasks\tcodex\n' $$ > "$(state_dir)/one"
  run_plugin
  assert_called 'sketchybar --set claude_waiting drawing=on label=\? omv$'
}

run_case 'should show the folder when one session waits' shows_the_folder
run_case "should read a session saved with its agent's name" reads_a_line_with_an_agent
run_case 'should hide a session marked seen at its current state' hides_a_seen_session
run_case 'should show a seen session again once its state changes' shows_a_seen_session_after_a_change
run_case "should ignore a seen file whose session has ended" ignores_a_seen_file_of_an_ended_session
run_case 'should hide the item when every session is working' hides_when_every_session_works
run_case 'should show an asking session before a done one, whatever the wait' shows_asking_before_done
run_case 'should mark an asking session with a question mark' marks_an_asking_session
run_case 'should count only waiting sessions in +N' counts_only_waiting_sessions
run_case 'should read a file saved before states existed as done' reads_an_old_file_as_done
run_case 'should show the oldest folder and +N when several wait' shows_the_oldest_and_a_count
run_case 'should hide the item when no session waits' hides_with_none
run_case 'should hide the item when the waiting Claude has ended' skips_an_ended_session
run_case 'should remove a session whose Claude has ended' removes_an_ended_session
run_case 'should cut a long folder name at 12 characters' cuts_a_long_folder
run_case 'should check the fit when the item changes' checks_the_fit
run_case 'should focus the waiting session on a click' focuses_on_click
finish
