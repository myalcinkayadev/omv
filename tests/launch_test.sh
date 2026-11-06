#!/usr/bin/env bash
# Behavior of the Hammerspoon launcher helper.

source "$(dirname "$0")/lib.sh"

readonly LAUNCH=$REPO_DIR/hammerspoon/.hammerspoon/launch.sh

opens_app_when_switch_fails() {
  stub aerospace 1
  run_in_sandbox "$LAUNCH" 2 -na Helium --args --new-window
  assert_called '^open -na Helium --args --new-window$'
}

switches_workspace_before_opening() {
  run_in_sandbox "$LAUNCH" 3 -a Zed
  [ "$(head -n 1 "$CALL_LOG")" = 'aerospace workspace 3' ] || fail "first call was: $(head -n 1 "$CALL_LOG")"
}

run_case 'should still open the app when the workspace switch fails' opens_app_when_switch_fails
run_case 'should switch workspace before opening the app when aerospace is available' switches_workspace_before_opening
finish
