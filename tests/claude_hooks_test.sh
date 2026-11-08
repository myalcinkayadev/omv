#!/usr/bin/env bash
# Behavior of claude-hooks.sh, which adds and removes the waiting hooks in Claude's settings.

source "$(dirname "$0")/lib.sh"

readonly SCRIPT=$REPO_DIR/claude-hooks.sh

settings() {
  echo "$HOME_DIR/.claude/settings.json"
}

# Settings someone already has: a model, and a SessionStart hook of their own.
existing_settings() {
  mkdir -p "$HOME_DIR/.claude"
  printf '%s\n' '{"model":"opus","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"my-start.sh"}]}]}}' > "$(settings)"
}

run_script() {
  run_in_sandbox PATH="$STUB_DIR:/usr/bin:/bin:/opt/homebrew/bin" "$SCRIPT" "$@"
}

command_for() {
  jq -r --arg event "$1" '[.hooks[$event][]?.hooks[]?.command] | join(",")' "$(settings)"
}

adds_wait_on_stop() {
  existing_settings
  run_script add
  [ "$(command_for Stop)" = '$HOME/.claude/claude-waiting.sh wait' ] || fail "Stop: $(command_for Stop)"
}

adds_wait_on_notification() {
  existing_settings
  run_script add
  [ "$(command_for Notification)" = '$HOME/.claude/claude-waiting.sh wait' ] || fail "Notification: $(command_for Notification)"
}

adds_clear_on_answers() {
  existing_settings
  run_script add
  local event
  for event in UserPromptSubmit PostToolUse SessionEnd; do
    [ "$(command_for "$event")" = '$HOME/.claude/claude-waiting.sh clear' ] || fail "$event: $(command_for "$event")"
  done
}

keeps_other_hooks() {
  existing_settings
  run_script add
  [ "$(command_for SessionStart)" = 'my-start.sh' ] || fail "SessionStart: $(command_for SessionStart)"
}

keeps_other_settings() {
  existing_settings
  run_script add
  [ "$(jq -r .model "$(settings)")" = opus ] || fail 'model setting lost'
}

adds_nothing_twice() {
  existing_settings
  run_script add
  run_script add
  [ "$(command_for Stop)" = '$HOME/.claude/claude-waiting.sh wait' ] || fail "Stop: $(command_for Stop)"
}

creates_missing_settings() {
  run_script add
  [ "$(command_for Stop)" = '$HOME/.claude/claude-waiting.sh wait' ] || fail 'no Stop hook in new settings'
}

removes_only_its_hooks() {
  existing_settings
  run_script add
  run_script remove
  [ "$(jq -c .hooks "$(settings)")" = '{"SessionStart":[{"hooks":[{"type":"command","command":"my-start.sh"}]}]}' ] || fail "left: $(jq -c .hooks "$(settings)")"
}

creates_nothing_on_remove() {
  run_script remove
  [ ! -e "$(settings)" ] || fail 'created settings while removing'
}

leaves_invalid_settings_unchanged() {
  mkdir -p "$HOME_DIR/.claude"
  printf 'not json' > "$(settings)"
  run_script add >/dev/null 2>&1 || true
  [ "$(cat "$(settings)")" = 'not json' ] || fail 'changed a file it could not read'
}

run_case 'should run the hook with wait when Claude stops' adds_wait_on_stop
run_case 'should run the hook with wait when Claude asks for approval' adds_wait_on_notification
run_case 'should run the hook with clear when you answer, a tool runs or the session ends' adds_clear_on_answers
run_case 'should keep hooks that are not its own' keeps_other_hooks
run_case 'should keep the other settings' keeps_other_settings
run_case 'should add nothing when run twice' adds_nothing_twice
run_case 'should create the settings when there are none' creates_missing_settings
run_case 'should remove only its own hooks' removes_only_its_hooks
run_case 'should create no settings when removing from none' creates_nothing_on_remove
run_case 'should leave settings it cannot read unchanged' leaves_invalid_settings_unchanged
finish
