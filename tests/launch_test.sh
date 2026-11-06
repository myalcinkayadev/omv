#!/usr/bin/env bash
# Behavior of the Hammerspoon launcher helper.

source "$(dirname "$0")/lib.sh"

readonly LAUNCH=$REPO_DIR/hammerspoon/.hammerspoon/launch.sh

runs_command_when_switch_fails() {
  stub aerospace 1
  run_in_sandbox "$LAUNCH" 3 open -na Helium --args --new-window
  assert_called '^open -na Helium --args --new-window$'
}

switches_workspace_before_running() {
  run_in_sandbox "$LAUNCH" 2 open -a Zed
  [ "$(head -n 1 "$CALL_LOG")" = 'aerospace workspace 2' ] || fail "first call was: $(head -n 1 "$CALL_LOG")"
}

run_case 'should run the given command when the workspace switch fails' runs_command_when_switch_fails
run_case 'should switch workspace before running the command when aerospace is available' switches_workspace_before_running
finish
