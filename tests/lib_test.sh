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

run_case 'should fail a case when an assertion before the last one fails' fails_on_early_assertion
run_case 'should fail a case when its last assertion fails' fails_on_last_assertion
run_case 'should pass a case when every assertion passes' passes_when_all_pass
run_case 'should give each case a fresh sandbox' gives_each_case_fresh_sandbox
run_case 'should make finish exit non-zero when any case failed' finish_fails_after_failed_case
finish
