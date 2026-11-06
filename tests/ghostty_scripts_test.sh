#!/usr/bin/env bash
# Behavior of the scripts that open Ghostty windows.

source "$(dirname "$0")/lib.sh"

readonly NEW_WINDOW=$REPO_DIR/ghostty/.config/ghostty/new-window.sh

asks_running_ghostty_for_window() {
  run_in_sandbox "$NEW_WINDOW"
  assert_called '^osascript .*new window'
}

passes_command_to_new_window() {
  run_in_sandbox "$NEW_WINDOW" /opt/homebrew/bin/btop
  assert_called '^osascript .*with configuration.* /opt/homebrew/bin/btop$'
}

closes_window_when_command_exits() {
  run_in_sandbox "$NEW_WINDOW" /opt/homebrew/bin/btop
  assert_called 'set initial input of windowConfig to "exec " & item 1 of argv'
}

starts_no_process_when_running() {
  run_in_sandbox "$NEW_WINDOW"
  assert_not_called '^open'
}

starts_ghostty_when_not_running() {
  stub pgrep 1
  run_in_sandbox "$NEW_WINDOW"
  assert_called '^open -a Ghostty$'
}

starts_ghostty_with_command_when_not_running() {
  stub pgrep 1
  run_in_sandbox "$NEW_WINDOW" /opt/homebrew/bin/btop
  assert_called '^open -a Ghostty --args -e /opt/homebrew/bin/btop$'
}

fails_when_osascript_fails() {
  stub osascript 1
  assert_exit_nonzero run_in_sandbox "$NEW_WINDOW"
}

run_case 'should ask running Ghostty for a new window when Ghostty is running' asks_running_ghostty_for_window
run_case 'should pass the command to the new window when one is given' passes_command_to_new_window
run_case 'should close the window when the command exits' closes_window_when_command_exits
run_case 'should not start a new process when Ghostty is running' starts_no_process_when_running
run_case 'should start Ghostty when it is not running' starts_ghostty_when_not_running
run_case 'should start Ghostty with the command when it is not running and one is given' starts_ghostty_with_command_when_not_running
run_case 'should exit non-zero when osascript fails' fails_when_osascript_fails
finish
