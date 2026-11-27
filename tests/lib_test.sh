#!/usr/bin/env bash
# Behavior of the test harness itself. Each sample case runs in a child bash,
# so its result never touches this file's own counters.

source "$(dirname "$0")/lib.sh"

# Runs a snippet with lib.sh loaded and prints its output.
run_with_harness() {
  bash -c "source '$REPO_DIR/tests/lib.sh'; $1" 2>&1
}

fails_on_early_assertion() {
  local output
  output=$(run_with_harness 'sample() { fail early; true; }; run_case sample sample')
  [[ $output == *'FAIL - sample'* ]] || fail "expected FAIL in: $output"
}

fails_on_last_assertion() {
  local output
  output=$(run_with_harness 'sample() { true; fail last; }; run_case sample sample')
  [[ $output == *'FAIL - sample'* ]] || fail "expected FAIL in: $output"
}

passes_when_all_pass() {
  local output
  output=$(run_with_harness 'sample() { true; true; }; run_case sample sample')
  [[ $output == *'ok   - sample'* ]] || fail "expected ok in: $output"
}

gives_each_case_fresh_sandbox() {
  local output
  output=$(run_with_harness 'first() { touch "$HOME_DIR/marker"; }; second() { [ ! -e "$HOME_DIR/marker" ]; }; run_case first first; run_case second second')
  [[ $output == *'ok   - second'* ]] || fail "expected a fresh sandbox in: $output"
}

finish_fails_after_failed_case() {
  assert_exit_nonzero run_with_harness 'sample() { false; }; run_case sample sample; finish'
}

logs_stub_call() {
  stub gh
  run_in_sandbox gh pr list --json number
  assert_called '^gh pr list --json number$'
}

exits_with_stub_code() {
  stub gh 3
  local code=0
  run_in_sandbox gh auth status || code=$?
  [ "$code" = 3 ] || fail "expected exit 3, got $code"
}

exits_zero_after_restub() {
  stub gh 3
  stub gh
  assert_exit_zero run_in_sandbox gh auth status
}

leaves_no_stub_after_removal() {
  stub gh
  remove_stub gh
  [ ! -e "$STUB_DIR/gh" ] || fail "gh is still stubbed"
}

keeps_stubs_to_their_case() {
  local output
  output=$(run_with_harness 'first() { stub aerospace 3; }; second() { run_in_sandbox aerospace; }; run_case first first; run_case second second')
  [[ $output == *'ok   - second'* ]] || fail "a stub's exit code reached the next case: $output"
}

blocks_real_command_behind_broken_stub() {
  remove_stub pkill
  : > "$STUB_DIR/pkill"
  local code=0
  run_in_sandbox pkill -x sketchybar 2>/dev/null || code=$?
  [ "$code" = 127 ] || fail "expected the guard's 127, got $code"
}

logs_blocked_real_command() {
  remove_stub defaults
  run_in_sandbox defaults write com.example key 1 2>/dev/null || true
  assert_called '^blocked defaults write com.example key 1$'
}

refuses_writes_through_shared_stub() {
  ! (echo 'exit 9' > "$STUB_DIR/aerospace") 2>/dev/null || fail "a write through the link changed the shared stub"
}

run_case 'should fail a case when an assertion before the last one fails' fails_on_early_assertion
run_case 'should fail a case when its last assertion fails' fails_on_last_assertion
run_case 'should pass a case when every assertion passes' passes_when_all_pass
run_case 'should give each case a fresh sandbox' gives_each_case_fresh_sandbox
run_case 'should make finish exit non-zero when any case failed' finish_fails_after_failed_case
run_case 'should log the stub name and arguments when it runs' logs_stub_call
run_case 'should exit with the code given to stub when it is not zero' exits_with_stub_code
run_case 'should exit zero when stub replaces a failing stub of the same name' exits_zero_after_restub
run_case 'should leave no stub behind when remove_stub runs' leaves_no_stub_after_removal
run_case "should keep a stub's exit code out of the next case" keeps_stubs_to_their_case
run_case 'should refuse a write through a stub link to the shared stub' refuses_writes_through_shared_stub
run_case "should block the real pkill when a case's own stub isn't executable" blocks_real_command_behind_broken_stub
run_case 'should log a blocked call when a system command has no stub' logs_blocked_real_command
finish
