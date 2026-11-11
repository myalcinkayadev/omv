#!/usr/bin/env bash
# Behavior of the Claude Code hook that records each session's state: working, asks (waits
# for your approval or answer) or done (finished, waits for your next prompt).
# ps is a stub, so the session's terminal is whatever a case says it is.

source "$(dirname "$0")/lib.sh"

readonly HOOK=$REPO_DIR/claude/.claude/claude-waiting.sh

state_dir() {
  echo "$HOME_DIR/.local/state/omv/claude-sessions"
}

state_file() {
  echo "$(state_dir)/abc-123"
}

# Claude (PID 4242) runs on ttys009; the hook's own shell has no terminal.
stub_ps() {
  cat > "$STUB_DIR/ps" <<'STUB'
#!/bin/sh
case "$*" in
  *"-p 4242"*) echo 'ttys009     1' ;;
  *) echo '??       4242' ;;
esac
STUB
  chmod +x "$STUB_DIR/ps"
}

# An event for session abc-123 (or the id given as $3), with a notification type when $2 is set.
event_json() {
  local type=${2:+,\"notification_type\":\"$2\"}
  printf '{"session_id":"%s","cwd":"/Users/me/workspace/omv","prompt":"secret prompt","transcript_path":"/secret/t.jsonl","hook_event_name":"%s"%s}' "${3:-abc-123}" "$1" "$type"
}

# The hook is installed with "wait" or "clear", but acts on the event's name.
run_hook() {
  run_in_sandbox "$HOOK" "${1:-wait}"
}

# A session saved in a given state since a fixed time, so no case depends on the clock.
save_session() {
  mkdir -p "$(state_dir)"
  printf '4242\t/dev/ttys009\tomv\t%s\t%s\n' "$2" "$1" > "$(state_file)"
}

state_of() {
  cut -f5 "$(state_file)"
}

since_of() {
  cut -f4 "$(state_file)"
}

records_working_on_prompt() {
  stub_ps
  event_json UserPromptSubmit | run_hook clear
  [ "$(state_of)" = working ] || fail "saved: $(cat "$(state_file)")"
}

records_done_on_stop() {
  stub_ps
  event_json Stop | run_hook wait
  [ "$(state_of)" = done ] || fail "saved: $(cat "$(state_file)")"
}

records_asks_on_permission() {
  stub_ps
  event_json Notification permission_prompt | run_hook wait
  [ "$(state_of)" = asks ] || fail "saved: $(cat "$(state_file)")"
}

records_asks_without_a_type() {
  stub_ps
  event_json Notification | run_hook wait
  [ "$(state_of)" = asks ] || fail "saved: $(cat "$(state_file)")"
}

marks_asking_working_after_a_tool() {
  stub_ps
  save_session asks 100
  event_json PostToolUse | run_hook clear
  [ "$(state_of)" = working ] || fail "saved: $(cat "$(state_file)")"
}

keeps_the_start_time_while_working() {
  stub_ps
  save_session working 100
  event_json PostToolUse | run_hook clear
  [ "$(since_of)" = 100 ] || fail "saved: $(cat "$(state_file)")"
}

removes_on_session_end() {
  stub_ps
  save_session working 100
  event_json SessionEnd | run_hook clear
  [ ! -e "$(state_file)" ] || fail 'state file left behind'
}

removes_the_seen_file_on_end() {
  stub_ps
  save_session done 100
  printf '100\n' > "$(state_dir)/.seen-abc-123"
  event_json SessionEnd | run_hook clear
  [ ! -e "$(state_dir)/.seen-abc-123" ] || fail 'seen file left behind'
}

ignores_a_notification_that_asks_nothing() {
  stub_ps
  save_session working 100
  event_json Notification agent_completed | run_hook wait
  [ "$(state_of)" = working ] || fail "saved: $(cat "$(state_file)")"
}

keeps_the_start_time_on_idle() {
  stub_ps
  save_session done 100
  event_json Notification idle_prompt | run_hook wait
  [ "$(since_of)" = 100 ] || fail "saved: $(cat "$(state_file)")"
}

records_done_on_idle_when_none_was_recorded() {
  stub_ps
  event_json Notification idle_prompt | run_hook wait
  [ "$(state_of)" = done ] || fail "saved: $(cat "$(state_file)")"
}

acts_on_the_event_not_the_argument() {
  stub_ps
  event_json Stop | run_hook clear
  [ "$(state_of)" = done ] || fail "saved: $(cat "$(state_file)")"
}

notifies_the_bar_when_waiting_starts() {
  stub_ps
  save_session working 100
  event_json Stop | run_hook wait
  assert_called 'sketchybar --trigger claude_waiting_change'
}

notifies_the_bar_when_waiting_ends() {
  stub_ps
  save_session done 100
  event_json UserPromptSubmit | run_hook clear
  assert_called 'sketchybar --trigger claude_waiting_change'
}

notifies_the_bar_when_asking_turns_done() {
  stub_ps
  save_session asks 100
  event_json Stop | run_hook wait
  assert_called 'sketchybar --trigger claude_waiting_change'
}

skips_the_bar_while_working() {
  stub_ps
  save_session working 100
  event_json PostToolUse | run_hook clear
  assert_not_called 'sketchybar'
}

skips_the_bar_when_a_working_session_starts() {
  stub_ps
  event_json UserPromptSubmit | run_hook clear
  assert_not_called 'sketchybar'
}

skips_the_bar_when_a_working_session_ends() {
  stub_ps
  save_session working 100
  event_json SessionEnd | run_hook clear
  assert_not_called 'sketchybar'
}

skips_the_bar_on_idle_that_changes_nothing() {
  stub_ps
  save_session done 100
  event_json Notification idle_prompt | run_hook wait
  assert_not_called 'sketchybar'
}

records_the_terminal_of_claude() {
  stub_ps
  event_json Stop | run_hook wait
  cut -f1-3 "$(state_file)" | grep -qx $'4242\t/dev/ttys009\tomv' || fail "saved: $(cat "$(state_file)")"
}

stores_nothing_else() {
  stub_ps
  event_json Stop | run_hook wait
  if grep -q secret "$(state_file)"; then fail 'stored the prompt or transcript'; fi
}

prints_nothing() {
  stub_ps
  local output
  output=$(event_json UserPromptSubmit | run_hook clear; event_json Stop | run_hook wait; event_json SessionEnd | run_hook clear)
  [ -z "$output" ] || fail "printed: $output"
}

refuses_a_path_in_the_session_id() {
  stub_ps
  event_json Stop '' '../../escape' | run_hook wait
  [ ! -e "$HOME_DIR/.local/escape" ] || fail 'wrote outside the state folder'
}

survives_invalid_json() {
  stub_ps
  printf 'not json' | assert_exit_zero run_hook wait
}

run_case 'should record a session as working when you send a prompt' records_working_on_prompt
run_case 'should record a session as done when Claude stops' records_done_on_stop
run_case 'should record a session as asking when Claude asks for approval' records_asks_on_permission
run_case 'should record a session as asking when the notification has no type' records_asks_without_a_type
run_case 'should mark an asking session working when a tool finishes' marks_asking_working_after_a_tool
run_case 'should keep the start time when a working session stays working' keeps_the_start_time_while_working
run_case 'should remove a session when it ends' removes_on_session_end
run_case 'should remove the seen file when the session ends' removes_the_seen_file_on_end
run_case 'should change nothing when the notification asks nothing of you' ignores_a_notification_that_asks_nothing
run_case 'should keep the start time when an idle notification follows a stop' keeps_the_start_time_on_idle
run_case 'should record a session as done when an idle notification arrives and none was recorded' records_done_on_idle_when_none_was_recorded
run_case "should act on the event's name whatever argument it was installed with" acts_on_the_event_not_the_argument
run_case 'should notify the bar when a session starts waiting' notifies_the_bar_when_waiting_starts
run_case 'should notify the bar when a session stops waiting' notifies_the_bar_when_waiting_ends
run_case 'should notify the bar when an asking session turns done' notifies_the_bar_when_asking_turns_done
run_case 'should leave the bar alone while a session keeps working' skips_the_bar_while_working
run_case 'should leave the bar alone when a working session starts' skips_the_bar_when_a_working_session_starts
run_case 'should leave the bar alone when a working session ends' skips_the_bar_when_a_working_session_ends
run_case 'should leave the bar alone when an idle notification changes nothing' skips_the_bar_on_idle_that_changes_nothing
run_case "should record Claude's PID, its terminal and the folder name" records_the_terminal_of_claude
run_case 'should store nothing from the prompt or transcript' stores_nothing_else
run_case 'should print nothing, since Claude reads hook output' prints_nothing
run_case 'should ignore a session id that is a path' refuses_a_path_in_the_session_id
run_case 'should exit zero when the input is invalid JSON' survives_invalid_json
finish
