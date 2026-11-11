#!/usr/bin/env bash
# Behavior of codex-hooks.sh, which adds and removes the waiting hooks in Codex's hooks.json.

source "$(dirname "$0")/lib.sh"

readonly SCRIPT=$REPO_DIR/codex-hooks.sh
readonly COMMAND='$HOME/.claude/claude-waiting.sh wait codex'

hooks_file() {
  echo "$HOME_DIR/.codex/hooks.json"
}

# Hooks someone already has: herdr's SessionStart hook.
existing_hooks() {
  mkdir -p "$HOME_DIR/.codex"
  printf '%s\n' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash herdr-agent-state.sh session"}]}]}}' > "$(hooks_file)"
}

run_script() {
  run_in_sandbox PATH="$STUB_DIR:/usr/bin:/bin:/opt/homebrew/bin" "$SCRIPT" "$@"
}

command_for() {
  jq -r --arg event "$1" '[.hooks[$event][]?.hooks[]?.command] | join(",")' "$(hooks_file)"
}

adds_the_four_hooks() {
  existing_hooks
  run_script add
  local event
  for event in UserPromptSubmit PostToolUse PermissionRequest Stop; do
    [ "$(command_for "$event")" = "$COMMAND" ] || fail "$event: $(command_for "$event")"
  done
}

keeps_other_hooks() {
  existing_hooks
  run_script add
  [ "$(command_for SessionStart)" = 'bash herdr-agent-state.sh session' ] || fail "SessionStart: $(command_for SessionStart)"
}

adds_nothing_twice() {
  existing_hooks
  run_script add
  run_script add
  [ "$(command_for Stop)" = "$COMMAND" ] || fail "Stop: $(command_for Stop)"
}

creates_missing_hooks_file() {
  run_script add
  [ "$(command_for Stop)" = "$COMMAND" ] || fail 'no Stop hook in a new file'
}

removes_only_its_hooks() {
  existing_hooks
  run_script add
  run_script remove
  [ "$(jq -c .hooks "$(hooks_file)")" = '{"SessionStart":[{"hooks":[{"type":"command","command":"bash herdr-agent-state.sh session"}]}]}' ] || fail "left: $(jq -c .hooks "$(hooks_file)")"
}

creates_nothing_on_remove() {
  run_script remove
  [ ! -e "$(hooks_file)" ] || fail 'created hooks.json while removing'
}

leaves_invalid_hooks_unchanged() {
  mkdir -p "$HOME_DIR/.codex"
  printf 'not json' > "$(hooks_file)"
  run_script add >/dev/null 2>&1 || true
  [ "$(cat "$(hooks_file)")" = 'not json' ] || fail 'changed a file it could not read'
}

run_case 'should add the four hooks' adds_the_four_hooks
run_case "should keep other hooks, such as herdr's" keeps_other_hooks
run_case 'should add nothing when run twice' adds_nothing_twice
run_case 'should create hooks.json when there is none' creates_missing_hooks_file
run_case 'should remove only its own hooks' removes_only_its_hooks
run_case 'should create no hooks.json when removing from none' creates_nothing_on_remove
run_case "should leave a hooks.json it can't read unchanged" leaves_invalid_hooks_unchanged
finish
