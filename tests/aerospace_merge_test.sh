#!/usr/bin/env bash
# Runs the aerospace.toml merge tests with luajit, then checks the script run as a command.

source "$(dirname "$0")/lib.sh"

builds_through_symlink() {
  ln -s "$REPO_DIR/install/aerospace_merge.lua" "$SANDBOX/merge.lua"
  luajit "$SANDBOX/merge.lua" "$REPO_DIR/config/aerospace/.config/aerospace/aerospace.toml" "$SANDBOX/none" >/dev/null \
    || fail 'the merge failed through a symlink'
}

DEFAULTS="$REPO_DIR/config/aerospace/.config/aerospace/aerospace.toml"

build() {
  luajit "$REPO_DIR/install/aerospace_merge.lua" "$DEFAULTS" "$SANDBOX/user.toml" "$SANDBOX/profile.toml" \
    "$SANDBOX/workspaces" "$SANDBOX/screens.toml"
}

builds_todays_workspaces_without_a_file() {
  local built
  built=$(build) || fail 'the build failed'
  [[ $built == *"alt-7 = 'workspace 7'"* && $built == *"persistent-workspaces = ['1', '2', '3', '4', '5', '6', '7']"* ]] \
    || fail "expected today's seven workspaces"
}

builds_the_listed_workspaces() {
  printf '1 = main\n2 = main\n8 = screen 2\n' > "$SANDBOX/workspaces"
  local built
  built=$(build) || fail 'the build failed'
  [[ $built == *"alt-8 = 'workspace 8'"* ]] || fail 'expected the keys of workspace 8'
  [[ $built != *"alt-7 ="* ]] || fail 'expected workspace 7 gone'
  [[ $built == *"8 = ['secondary', 'main']"* ]] || fail 'expected workspace 8 pinned to screen 2'
}

applies_the_screens_after_the_users_file() {
  printf '[workspace-to-monitor-force-assignment]\n1 = %s\n' "'DELL'" > "$SANDBOX/user.toml"
  printf '[workspace-to-monitor-force-assignment]\n1 = [2, %s]\n' "'main'" > "$SANDBOX/screens.toml"
  local built
  built=$(build) || fail 'the build failed'
  [[ $built == *"1 = [2, 'main']"* && $built != *"1 = 'DELL'"* ]] || fail 'expected the resolved screens to win'
}

keeps_the_users_own_workspace_key() {
  printf '1 = main\n8 = main\n' > "$SANDBOX/workspaces"
  printf '[mode.main.binding]\nalt-8 = %s\n' "'layout tiles'" > "$SANDBOX/user.toml"
  local built
  built=$(build) || fail 'the build failed'
  [[ $built == *"alt-8 = 'layout tiles'"* && $built != *"alt-8 = 'workspace 8'"* ]] || fail "expected the user's alt-8 to win"
}

status=0
luajit "$REPO_DIR/tests/aerospace_merge_test.lua" "$REPO_DIR" || status=1
run_case 'should build when the merge is run through a symlink to it' builds_through_symlink
run_case "should build today's seven workspaces without a workspaces file" builds_todays_workspaces_without_a_file
run_case 'should build the keys and pins of the listed workspaces only' builds_the_listed_workspaces
run_case "should apply the resolved screens after the user's file" applies_the_screens_after_the_users_file
run_case "should keep the user's own binding on a workspace key" keeps_the_users_own_workspace_key
finish || status=1
exit "$status"
