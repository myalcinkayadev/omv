#!/usr/bin/env bash
# Behavior of the bar item that shows the checks on your own open pull requests.
# gh is a stub that prints what gh's --jq filter would: no case reaches the network.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/config/sketchybar/.config/sketchybar/plugins/github_ci.sh

# A gh that prints the given lines, one per pull request, or fails like gh does offline.
stub_gh() {
  local lines=$1 exit_code=${2:-0}
  printf '%b' "$lines" > "$SANDBOX/gh-output"
  own_stub gh
  cat > "$STUB_DIR/gh" <<STUB
#!/bin/sh
echo "gh \$*" >> "$CALL_LOG"
[ $exit_code -eq 0 ] || { echo 'error connecting to api.github.com' >&2; exit $exit_code; }
cat "$SANDBOX/gh-output"
STUB
  chmod +x "$STUB_DIR/gh"
}

state_file() {
  echo "$HOME_DIR/.local/state/omv/github-ci"
}

passed_file() {
  echo "$HOME_DIR/.local/state/omv/github-ci-passed"
}

# The state a previous run left behind.
previous_state() {
  mkdir -p "$HOME_DIR/.local/state/omv"
  printf '%b' "$1" > "$(state_file)"
}

run_plugin() {
  run_in_sandbox NAME=github_ci GH="$STUB_DIR/gh" "$@" "$PLUGIN"
}

readonly FAILING='FAILURE\thttps://github.com/acme/api/pull/42\tacme/api#42\tFix login\n'
readonly PASSING='SUCCESS\thttps://github.com/acme/api/pull/42\tacme/api#42\tFix login\n'
readonly RUNNING='PENDING\thttps://github.com/acme/web/pull/7\tacme/web#7\tAdd docs\n'

shows_the_failing_count() {
  stub_gh "$FAILING$RUNNING"
  stub hs
  run_plugin
  assert_called 'sketchybar --set github_ci drawing=on icon=.* label=1 background.drawing=on'
}

counts_errors_as_failing() {
  stub_gh 'ERROR\thttps://github.com/acme/api/pull/1\tacme/api#1\tA\nFAILURE\thttps://github.com/acme/api/pull/2\tacme/api#2\tB\n'
  stub hs
  run_plugin
  assert_called 'sketchybar --set github_ci drawing=on icon=.* label=2 '
}

shows_the_running_count_when_none_fail() {
  stub_gh "$PASSING$RUNNING"
  stub hs
  run_plugin
  assert_called 'sketchybar --set github_ci drawing=on icon=.* label=1 background.drawing=off'
}

hides_when_every_check_passed() {
  stub_gh "$PASSING"
  stub hs
  run_plugin
  assert_called 'sketchybar --set github_ci drawing=off'
}

hides_without_pull_requests() {
  stub_gh ''
  stub hs
  run_plugin
  assert_called 'sketchybar --set github_ci drawing=off'
}

asks_for_your_open_pull_requests() {
  stub_gh "$PASSING"
  stub hs
  run_plugin
  assert_called 'gh api graphql .*is:pr is:open author:@me'
}

saves_each_pull_request() {
  stub_gh "$FAILING$RUNNING"
  stub hs
  run_plugin
  [ "$(wc -l < "$(state_file)" | tr -d ' ')" = 2 ] || fail "expected 2 lines in the state file: $(cat "$(state_file)")"
}

hides_when_gh_fails() {
  stub_gh "$FAILING" 1
  run_plugin
  assert_called 'sketchybar --set github_ci drawing=off'
}

keeps_the_state_when_gh_fails() {
  previous_state "$FAILING"
  stub_gh '' 1
  run_plugin
  grep -q '^FAILURE' "$(state_file)" || fail "expected the failing line to stay: $(cat "$(state_file)")"
}

exits_zero_when_gh_fails() {
  stub_gh '' 1
  assert_exit_zero run_plugin
}

hides_without_gh() {
  run_in_sandbox NAME=github_ci GH="$SANDBOX/missing/gh" "$PLUGIN"
  assert_called 'sketchybar --set github_ci drawing=off'
}

notices_a_failing_pull_request_that_passes() {
  previous_state "$FAILING"
  stub_gh "$PASSING"
  stub hs
  run_plugin
  assert_called "hs -t 2 -c omvCiPassed\(\)"
}

names_the_passed_pull_request() {
  previous_state "$FAILING"
  stub_gh "$PASSING"
  stub hs
  run_plugin
  grep -q 'acme/api#42' "$(passed_file)" || fail "expected acme/api#42 in the passed file"
}

skips_the_notice_on_the_first_run() {
  stub_gh "$PASSING"
  stub hs
  run_plugin
  assert_not_called '^hs '
}

skips_the_notice_when_it_passed_before() {
  previous_state "$PASSING"
  stub_gh "$PASSING"
  stub hs
  run_plugin
  assert_not_called '^hs '
}

skips_the_notice_for_a_running_one_that_passes() {
  previous_state "$RUNNING"
  stub_gh 'SUCCESS\thttps://github.com/acme/web/pull/7\tacme/web#7\tAdd docs\n'
  stub hs
  run_plugin
  assert_not_called '^hs '
}

checks_the_fit() {
  stub_gh "$FAILING"
  stub hs
  run_plugin
  assert_called 'sketchybar --trigger bar_fit'
}

opens_the_card_on_click() {
  stub hs
  run_plugin SENDER=mouse.clicked
  assert_called "hs -t 2 -c omvToggleCi\(\)"
}

skips_gh_on_click() {
  stub_gh "$FAILING"
  stub hs
  run_plugin SENDER=mouse.clicked
  assert_not_called '^gh '
}

run_case 'should show the failing count as a pill when a check fails' shows_the_failing_count
run_case 'should count a check that errored as failing' counts_errors_as_failing
run_case 'should show the running count when no check fails' shows_the_running_count_when_none_fail
run_case 'should hide the item when every check passed' hides_when_every_check_passed
run_case 'should hide the item when you have no open pull requests' hides_without_pull_requests
run_case 'should ask gh for your own open pull requests' asks_for_your_open_pull_requests
run_case 'should save one line per pull request for the card' saves_each_pull_request
run_case 'should hide the item when gh fails' hides_when_gh_fails
run_case 'should keep the last state when gh fails' keeps_the_state_when_gh_fails
run_case 'should exit zero when gh fails' exits_zero_when_gh_fails
run_case 'should hide the item when gh is not installed' hides_without_gh
run_case 'should send a notice when a failing pull request passes' notices_a_failing_pull_request_that_passes
run_case 'should name the passed pull request for the notice' names_the_passed_pull_request
run_case 'should send no notice on the first run' skips_the_notice_on_the_first_run
run_case 'should send no notice when the checks passed before too' skips_the_notice_when_it_passed_before
run_case 'should send no notice when a running check passes' skips_the_notice_for_a_running_one_that_passes
run_case 'should check the fit when the item changes' checks_the_fit
run_case 'should open the card on a click' opens_the_card_on_click
run_case 'should not call gh on a click' skips_gh_on_click
finish
