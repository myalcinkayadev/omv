#!/usr/bin/env bash
# Behavior of the Claude Code hook that marks a session as waiting for you.
# ps is a stub, so the session's terminal is whatever a case says it is.

source "$(dirname "$0")/lib.sh"

readonly HOOK=$REPO_DIR/claude/.claude/claude-waiting.sh

state_dir() {
  echo "$HOME_DIR/.local/state/omv/claude-waiting"
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

event_json() {
  printf '{"session_id":"%s","cwd":"/Users/me/workspace/omv","prompt":"secret prompt","transcript_path":"/secret/t.jsonl","hook_event_name":"Stop"}' "${1:-abc-123}"
}

run_hook() {
  run_in_sandbox "$HOOK" "$@"
}

records_a_waiting_session() {
  stub_ps
  event_json | run_hook wait
  [ -f "$(state_dir)/abc-123" ] || fail 'no state file'
}

records_the_terminal_of_claude() {
  stub_ps
  event_json | run_hook wait
  cut -f1-3 "$(state_dir)/abc-123" | grep -qx $'4242\t/dev/ttys009\tomv' || fail "saved: $(cat "$(state_dir)/abc-123")"
}

stores_nothing_else() {
  stub_ps
  event_json | run_hook wait
  if grep -q secret "$(state_dir)/abc-123"; then fail 'stored the prompt or transcript'; fi
}

notifies_the_bar() {
  stub_ps
  event_json | run_hook wait
  assert_called 'sketchybar --trigger claude_waiting_change'
}

clears_a_session() {
  stub_ps
  event_json | run_hook wait
  event_json | run_hook clear
  [ ! -e "$(state_dir)/abc-123" ] || fail 'state file left behind'
}

skips_the_bar_when_nothing_waited() {
  stub_ps
  event_json | run_hook clear
  assert_not_called 'sketchybar'
}

prints_nothing() {
  stub_ps
  local output
  output=$(event_json | run_hook wait; event_json | run_hook clear)
  [ -z "$output" ] || fail "printed: $output"
}

refuses_a_path_in_the_session_id() {
  stub_ps
  event_json '../../escape' | run_hook wait
  [ ! -e "$HOME_DIR/.local/escape" ] || fail 'wrote outside the state folder'
}

survives_invalid_json() {
  stub_ps
  printf 'not json' | assert_exit_zero run_hook wait
}

run_case 'should record a session when Claude waits' records_a_waiting_session
run_case "should record Claude's PID, its terminal and the folder name" records_the_terminal_of_claude
run_case 'should store nothing from the prompt or transcript' stores_nothing_else
run_case 'should notify the bar when a session waits' notifies_the_bar
run_case 'should clear a session when you answer it' clears_a_session
run_case 'should leave the bar alone when the cleared session was not waiting' skips_the_bar_when_nothing_waited
run_case 'should print nothing, since Claude reads hook output' prints_nothing
run_case 'should ignore a session id that is a path' refuses_a_path_in_the_session_id
run_case 'should exit zero when the input is invalid JSON' survives_invalid_json
finish
