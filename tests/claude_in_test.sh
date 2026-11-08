#!/usr/bin/env bash
# Behavior of claude-in.sh, which starts Claude Code in a folder for the Agents card.

source "$(dirname "$0")/lib.sh"

readonly SCRIPT=$REPO_DIR/hammerspoon/.hammerspoon/claude-in.sh

# The login shell is a stub that logs the folder it runs in and what it was asked to run.
stub_shell() {
  cat > "$STUB_DIR/login-shell" <<STUB
#!/bin/sh
echo "shell \$(pwd) \$*" >> "$CALL_LOG"
STUB
  chmod +x "$STUB_DIR/login-shell"
}

claude_in() {
  run_in_sandbox SHELL="$STUB_DIR/login-shell" "$SCRIPT" "$@"
}

runs_in_the_folder() {
  stub_shell
  mkdir -p "$SANDBOX/my project"
  claude_in "$SANDBOX/my project"
  assert_called "^shell $SANDBOX/my project "
}

runs_claude_through_a_login_shell() {
  stub_shell
  claude_in "$SANDBOX"
  assert_called '^shell .* -lic claude "\$@" claude$'
}

passes_continue_on() {
  stub_shell
  claude_in "$SANDBOX" --continue
  assert_called '^shell .* -lic claude "\$@" claude --continue$'
}

fails_without_the_folder() {
  stub_shell
  assert_exit_nonzero claude_in "$SANDBOX/missing"
}

run_case "should start in the given folder" runs_in_the_folder
run_case "should run claude through a login shell, so its PATH is set" runs_claude_through_a_login_shell
run_case "should pass --continue on to claude" passes_continue_on
run_case "should fail when the folder doesn't exist" fails_without_the_folder
finish
