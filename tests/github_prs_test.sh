#!/usr/bin/env bash
# Behavior of the bar item that counts pull requests waiting for your review.
# gh is a stub: no case reaches the network.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/github_prs.sh

# A gh that prints how many pull requests wait, or fails like gh does when offline.
stub_gh() {
  local count=$1 exit_code=${2:-0}
  cat > "$STUB_DIR/gh" <<STUB
#!/bin/sh
echo "gh \$*" >> "$CALL_LOG"
[ $exit_code -eq 0 ] || { echo 'error connecting to api.github.com' >&2; exit $exit_code; }
echo $count
STUB
  chmod +x "$STUB_DIR/gh"
}

run_plugin() {
  run_in_sandbox NAME=github_prs GH="$STUB_DIR/gh" "$@" "$PLUGIN"
}

shows_the_count() {
  stub_gh 3
  run_plugin
  assert_called 'sketchybar --set github_prs drawing=on label=3'
}

asks_for_review_requests() {
  stub_gh 3
  run_plugin
  assert_called 'gh search prs --review-requested=@me --state=open'
}

hides_with_none() {
  stub_gh 0
  run_plugin
  assert_called 'sketchybar --set github_prs drawing=off'
}

hides_when_gh_fails() {
  stub_gh 3 1
  run_plugin
  assert_called 'sketchybar --set github_prs drawing=off'
}

exits_zero_when_gh_fails() {
  stub_gh 3 1
  assert_exit_zero run_plugin
}

hides_without_gh() {
  run_in_sandbox NAME=github_prs GH="$SANDBOX/missing/gh" "$PLUGIN"
  assert_called 'sketchybar --set github_prs drawing=off'
}

hides_on_unexpected_output() {
  stub_gh 'not-a-number'
  run_plugin
  assert_called 'sketchybar --set github_prs drawing=off'
}

checks_the_fit() {
  stub_gh 3
  run_plugin
  assert_called 'sketchybar --trigger bar_fit'
}

opens_the_card_on_click() {
  stub hs
  run_plugin SENDER=mouse.clicked
  assert_called "hs -c omvTogglePrs\(\)"
}

skips_gh_on_click() {
  stub_gh 3
  stub hs
  run_plugin SENDER=mouse.clicked
  assert_not_called '^gh '
}

run_case 'should show the count when pull requests wait for review' shows_the_count
run_case 'should ask gh for open pull requests requesting your review' asks_for_review_requests
run_case 'should hide the item when no pull requests wait' hides_with_none
run_case 'should hide the item when gh fails' hides_when_gh_fails
run_case 'should exit zero when gh fails' exits_zero_when_gh_fails
run_case 'should hide the item when gh is not installed' hides_without_gh
run_case 'should hide the item when gh prints something other than a count' hides_on_unexpected_output
run_case 'should check the fit when the item is drawn' checks_the_fit
run_case 'should open the pull request card on a click' opens_the_card_on_click
run_case 'should not call gh on a click' skips_gh_on_click
finish
