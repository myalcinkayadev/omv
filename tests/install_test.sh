#!/usr/bin/env bash
# Behavior of install.sh, against stubs and a temporary HOME.

source "$(dirname "$0")/lib.sh"

readonly INSTALL=$REPO_DIR/install.sh

add_conflicting_file() {
  mkdir -p "$HOME_DIR/.config/aerospace"
  echo 'mine' > "$HOME_DIR/.config/aerospace/aerospace.toml"
}

adds_codex_hooks() {
  use_real_stow
  mkdir -p "$HOME_DIR/.codex"
  run_in_sandbox PATH="$STUB_DIR:/usr/bin:/bin:/opt/homebrew/bin" "$INSTALL" >/dev/null
  grep -q claude-waiting.sh "$HOME_DIR/.codex/hooks.json" || fail 'Codex hooks were not added'
}

leaves_codex_alone() {
  use_real_stow
  run_in_sandbox PATH="$STUB_DIR:/usr/bin:/bin:/opt/homebrew/bin" "$INSTALL" >/dev/null
  [ ! -e "$HOME_DIR/.codex" ] || fail 'created ~/.codex'
}

links_opencode_plugin() {
  use_real_stow
  mkdir -p "$HOME_DIR/.config/opencode"
  run_in_sandbox "$INSTALL" >/dev/null
  [ -L "$HOME_DIR/.config/opencode/plugins/omv-agent-state.js" ] || fail 'plugin not linked'
}

links_pi_extension() {
  use_real_stow
  mkdir -p "$HOME_DIR/.pi/agent"
  run_in_sandbox "$INSTALL" >/dev/null
  [ -L "$HOME_DIR/.pi/agent/extensions/omv-agent-state.ts" ] || fail 'extension not linked'
}

links_no_agent_plugin() {
  use_real_stow
  run_in_sandbox "$INSTALL" >/dev/null
  [ ! -e "$HOME_DIR/.config/opencode" ] && [ ! -e "$HOME_DIR/.pi" ] || fail "linked a plugin for an agent that isn't set up"
}

fails_without_brew() {
  remove_stub brew
  assert_exit_nonzero run_in_sandbox "$INSTALL"
}

fails_without_stow() {
  remove_stub stow
  assert_exit_nonzero run_in_sandbox "$INSTALL"
}

trusts_taps_before_installing() {
  run_in_sandbox "$INSTALL" >/dev/null
  local last_trust first_install
  last_trust=$(grep -n '^brew trust' "$CALL_LOG" | tail -n 1 | cut -d: -f1)
  first_install=$(grep -n '^brew install' "$CALL_LOG" | head -n 1 | cut -d: -f1)
  assert_called '^brew trust --tap nikitabobko/tap$'
  assert_called '^brew trust --tap felixkratz/formulae$'
  [ "$last_trust" -lt "$first_install" ] || fail 'a tap was trusted after brew install ran'
}

links_all_packages() {
  use_real_stow
  run_in_sandbox "$INSTALL" >/dev/null
  local link
  for link in .config/aerospace .config/sketchybar .config/ghostty .config/nvim .config/btop .hammerspoon .claude/bar-usage.sh .config/swipeareospace; do
    [ -L "$HOME_DIR/$link" ] || fail "not linked: $link"
  done
}

keeps_claude_dir_real() {
  use_real_stow
  run_in_sandbox "$INSTALL" >/dev/null
  [ ! -L "$HOME_DIR/.claude" ] || fail '.claude became a link into the repo'
}

adds_usage_line() {
  use_real_stow
  mkdir -p "$HOME_DIR/.claude"
  printf 'input=$(cat)\n' > "$HOME_DIR/.claude/statusline-wrapper.sh"
  run_in_sandbox "$INSTALL" >/dev/null
  grep -q bar-usage "$HOME_DIR/.claude/statusline-wrapper.sh" || fail 'line was not added'
}

adds_waiting_hooks() {
  use_real_stow
  run_in_sandbox "$INSTALL" >/dev/null
  grep -q claude-waiting.sh "$HOME_DIR/.claude/settings.json" || fail 'hooks were not added'
}

applies_macos_settings() {
  run_in_sandbox "$INSTALL" >/dev/null
  assert_called '^defaults write NSGlobalDomain _HIHideMenuBar -bool true$'
  assert_called '^defaults write com\.apple\.spaces spans-displays -bool true$'
}

trusts_swipe_tap() {
  run_in_sandbox "$INSTALL" >/dev/null
  assert_called '^brew trust --tap mediosz/tap$'
}

installs_borders() {
  run_in_sandbox "$INSTALL" >/dev/null
  assert_called '^brew install felixkratz/formulae/borders$'
}

installs_swipe_cask() {
  run_in_sandbox "$INSTALL" >/dev/null
  assert_called '^brew install --cask mediosz/tap/swipeaerospace$'
}

turns_off_builtin_trackpad_swipe() {
  run_in_sandbox "$INSTALL" >/dev/null
  assert_called '^defaults write com\.apple\.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture -int 0$'
}

turns_off_magic_trackpad_swipe() {
  run_in_sandbox "$INSTALL" >/dev/null
  assert_called '^defaults write com\.apple\.driver\.AppleBluetoothMultitouch\.trackpad TrackpadThreeFingerHorizSwipeGesture -int 0$'
}

turns_off_current_host_swipe() {
  run_in_sandbox "$INSTALL" >/dev/null
  assert_called '^defaults -currentHost write NSGlobalDomain com\.apple\.trackpad\.threeFingerHorizSwipeGesture -int 0$'
}

turns_off_window_animations() {
  run_in_sandbox "$INSTALL" >/dev/null
  assert_called '^defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false$'
}

enables_drag_from_anywhere() {
  run_in_sandbox "$INSTALL" >/dev/null
  assert_called '^defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true$'
}

is_safe_to_rerun() {
  use_real_stow
  run_in_sandbox "$INSTALL" >/dev/null
  assert_exit_zero run_in_sandbox "$INSTALL"
}

stops_before_settings_on_stow_conflict() {
  use_real_stow
  add_conflicting_file
  run_in_sandbox "$INSTALL" >/dev/null 2>&1 || true
  assert_not_called '^defaults write'
}

fails_on_stow_conflict() {
  use_real_stow
  add_conflicting_file
  assert_exit_nonzero run_in_sandbox "$INSTALL"
}

reports_stow_conflict() {
  use_real_stow
  add_conflicting_file
  local output
  output=$(run_in_sandbox "$INSTALL" 2>&1 || true)
  [[ $output == *"install.sh: stow could not link"* ]] || fail "missing report in: $output"
}

run_case 'should exit non-zero when brew is missing' fails_without_brew
run_case 'should exit non-zero when stow is missing' fails_without_stow
run_case 'should trust the taps before installing' trusts_taps_before_installing
run_case 'should link all eight packages when the target is clean' links_all_packages
run_case 'should keep .claude a real directory when linking' keeps_claude_dir_real
run_case 'should add the usage line when installing' adds_usage_line
run_case "should add the waiting hooks to Claude's settings when installing" adds_waiting_hooks
run_case 'should apply both macOS settings when linking succeeds' applies_macos_settings
run_case 'should trust mediosz/tap' trusts_swipe_tap
run_case 'should install borders' installs_borders
run_case 'should install the swipeaerospace cask' installs_swipe_cask
run_case 'should turn off the three-finger swipe on the built-in trackpad' turns_off_builtin_trackpad_swipe
run_case 'should turn off the three-finger swipe on the Magic Trackpad' turns_off_magic_trackpad_swipe
run_case 'should turn off the three-finger swipe for the current host' turns_off_current_host_swipe
run_case 'should turn off window-opening animations' turns_off_window_animations
run_case 'should let Ctrl+Cmd drag a window from anywhere' enables_drag_from_anywhere
run_case 'should succeed when executed twice' is_safe_to_rerun
run_case 'should exit non-zero when stow finds a conflicting real file' fails_on_stow_conflict
run_case 'should skip macOS and trackpad settings when stow finds a conflicting real file' stops_before_settings_on_stow_conflict
run_case 'should report the failure when stow finds a conflicting real file' reports_stow_conflict
run_case 'should add the Codex hooks when Codex is set up' adds_codex_hooks
run_case "should leave Codex alone when it isn't set up" leaves_codex_alone
run_case 'should link the OpenCode plugin when OpenCode is set up' links_opencode_plugin
run_case 'should link the pi extension when pi is set up' links_pi_extension
run_case "should link no agent plugin when no agent is set up" links_no_agent_plugin
finish
