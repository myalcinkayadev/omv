#!/usr/bin/env bash
# Behavior of the bar item that counts outdated Homebrew packages, and of the script its click
# opens in Ghostty. brew is a stub: no case updates, upgrades or reaches the network.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/config/sketchybar/.config/sketchybar/plugins/brew_outdated.sh
readonly UPGRADE=$REPO_DIR/config/hammerspoon/brew-upgrade.sh

# A brew that logs each call with HOMEBREW_NO_AUTO_UPDATE, prints the given lines and exits
# with the given code. Warnings go to stderr, as brew's own do.
stub_brew() {
  local lines=$1 exit_code=${2:-0}
  printf '%b' "$lines" > "$SANDBOX/outdated"
  cat > "$STUB_DIR/brew" <<STUB
#!/bin/sh
echo "brew \$* no_auto_update=\${HOMEBREW_NO_AUTO_UPDATE:-}" >> "$CALL_LOG"
echo 'Warning: some tap is not trusted' >&2
cat "$SANDBOX/outdated"
exit $exit_code
STUB
  chmod +x "$STUB_DIR/brew"
}

stamp() {
  echo "$HOME_DIR/.local/state/omv/brew-outdated"
}

# The last count, seconds ago.
counted_ago() {
  mkdir -p "$(dirname "$(stamp)")"
  echo $(($(date +%s) - $1)) > "$(stamp)"
}

run_plugin() {
  run_in_sandbox NAME=brew_outdated BREW="$STUB_DIR/brew" "$@" "$PLUGIN"
}

hides_with_none() {
  stub_brew ''
  run_plugin SENDER=routine
  assert_called '^sketchybar --set brew_outdated drawing=off$'
}

shows_the_count() {
  stub_brew 'git\nnode\nwget\n'
  run_plugin SENDER=routine
  assert_called '^sketchybar --set brew_outdated drawing=on label=3$'
}

ignores_blank_lines() {
  stub_brew '\ngit\n\n  \nnode\n'
  run_plugin SENDER=routine
  assert_called '^sketchybar --set brew_outdated drawing=on label=2$'
}

ignores_warnings_on_stderr() {
  stub_brew 'git\n'
  run_plugin SENDER=routine
  assert_called '^sketchybar --set brew_outdated drawing=on label=1$'
}

hides_when_brew_fails() {
  stub_brew 'git\n' 1
  run_plugin SENDER=routine
  assert_called '^sketchybar --set brew_outdated drawing=off$'
}

exits_zero_when_brew_fails() {
  stub_brew 'git\n' 1
  assert_exit_zero run_plugin SENDER=routine
}

keeps_the_time_when_brew_fails() {
  stub_brew 'git\n' 1
  counted_ago 7200
  local before
  before=$(cat "$(stamp)")
  run_plugin SENDER=routine
  [ "$(cat "$(stamp)")" = "$before" ] || fail "the time of the last count changed"
}

hides_without_brew() {
  run_in_sandbox NAME=brew_outdated BREW="$SANDBOX/missing/brew" SENDER=routine "$PLUGIN"
  assert_called '^sketchybar --set brew_outdated drawing=off$'
}

counts_without_auto_update() {
  stub_brew 'git\n'
  run_plugin SENDER=routine
  assert_called '^brew outdated --quiet no_auto_update=1$'
}

never_runs_brew_update() {
  stub_brew 'git\n'
  run_plugin SENDER=routine
  assert_not_called '^brew update'
}

skips_a_wake_within_the_hour() {
  stub_brew 'git\n'
  counted_ago 600
  run_plugin SENDER=system_woke
  assert_not_called '^brew '
}

counts_on_a_wake_after_the_hour() {
  stub_brew 'git\n'
  counted_ago 7200
  run_plugin SENDER=system_woke
  assert_called '^brew outdated'
}

counts_on_a_wake_without_a_last_count() {
  stub_brew 'git\n'
  run_plugin SENDER=system_woke
  assert_called '^brew outdated'
}

counts_on_the_timer_within_the_hour() {
  stub_brew 'git\n'
  counted_ago 600
  run_plugin SENDER=routine
  assert_called '^brew outdated'
}

keeps_the_time_of_the_count() {
  stub_brew 'git\n'
  run_plugin SENDER=routine
  [ -n "$(cat "$(stamp)" 2>/dev/null)" ] || fail "no time kept in $(stamp)"
}

checks_the_fit() {
  stub_brew 'git\n'
  run_plugin SENDER=routine
  assert_called '^sketchybar --trigger bar_fit$'
}

opens_the_upgrade_on_click() {
  stub hs
  run_plugin SENDER=mouse.clicked
  assert_called '^hs -c omvBrewUpgrade\(\)$'
}

skips_brew_on_click() {
  stub_brew 'git\n'
  stub hs
  run_plugin SENDER=mouse.clicked
  assert_not_called '^brew '
}

marks_the_count_stale_on_click() {
  stub hs
  counted_ago 600
  run_plugin SENDER=mouse.clicked
  [ ! -e "$(stamp)" ] || fail "the last count is still kept after a click"
}

upgrades_in_the_window() {
  echo | run_in_sandbox "$UPGRADE" >/dev/null
  assert_called '^brew upgrade$'
}

counts_again_after_the_upgrade() {
  echo | run_in_sandbox "$UPGRADE" >/dev/null
  assert_called '^sketchybar --trigger brew_outdated_change$'
}

counts_again_after_a_failed_upgrade() {
  stub brew 1
  echo | run_in_sandbox "$UPGRADE" >/dev/null
  assert_called '^sketchybar --trigger brew_outdated_change$'
}

run_case 'should hide the item when no package is outdated' hides_with_none
run_case 'should show the count when packages are outdated' shows_the_count
run_case 'should count only non-blank lines when brew prints blank ones' ignores_blank_lines
run_case 'should ignore warnings when brew prints them to stderr' ignores_warnings_on_stderr
run_case 'should stay hidden when brew fails' hides_when_brew_fails
run_case 'should exit zero when brew fails' exits_zero_when_brew_fails
run_case 'should keep the last count time when brew fails' keeps_the_time_when_brew_fails
run_case 'should stay hidden when brew is missing' hides_without_brew
run_case 'should count with auto-update off when it asks brew' counts_without_auto_update
run_case 'should never run brew update when it counts' never_runs_brew_update
run_case 'should skip a wake-time count when the last one is under an hour old' skips_a_wake_within_the_hour
run_case 'should count on a wake when the last count is over an hour old' counts_on_a_wake_after_the_hour
run_case 'should count on a wake when there is no last count' counts_on_a_wake_without_a_last_count
run_case 'should count on the timer when the last count is under an hour old' counts_on_the_timer_within_the_hour
run_case 'should keep the time when it counts' keeps_the_time_of_the_count
run_case 'should check the fit when the item changes' checks_the_fit
run_case 'should open the upgrade on a click' opens_the_upgrade_on_click
run_case 'should not call brew on a click' skips_brew_on_click
run_case 'should mark the count stale on a click' marks_the_count_stale_on_click
run_case 'should run brew upgrade when the window opens' upgrades_in_the_window
run_case 'should have the item count again when the upgrade ends' counts_again_after_the_upgrade
run_case 'should have the item count again when the upgrade fails' counts_again_after_a_failed_upgrade
finish
