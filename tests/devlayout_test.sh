#!/usr/bin/env bash
# Runs the dev layout tests, and checks shell-in.sh opens a shell in the folder it's given.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/devlayout_test.lua" "$REPO_DIR" || failed=$((failed + 1))

readonly SHELL_IN=$REPO_DIR/hammerspoon/.hammerspoon/shell-in.sh

opens_the_shell_in_the_folder() {
  mkdir -p "$SANDBOX/my project"
  printf '#!/bin/sh\npwd > "%s/where"\n' "$SANDBOX" > "$SANDBOX/fake-shell"
  chmod +x "$SANDBOX/fake-shell"
  run_in_sandbox /usr/bin/env SHELL="$SANDBOX/fake-shell" "$SHELL_IN" "$SANDBOX/my project" < /dev/null
  [ "$(cat "$SANDBOX/where")" = "$SANDBOX/my project" ] || fail "shell ran in: $(cat "$SANDBOX/where" 2>/dev/null)"
}

fails_for_a_missing_folder() {
  assert_exit_nonzero run_in_sandbox "$SHELL_IN" "$SANDBOX/nowhere"
}

run_case 'should open the shell in the folder it is given' opens_the_shell_in_the_folder
run_case 'should exit non-zero for a folder that does not exist' fails_for_a_missing_folder
finish
