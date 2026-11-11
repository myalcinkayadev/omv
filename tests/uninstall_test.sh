#!/usr/bin/env bash
# Behavior of uninstall.sh, against stubs and a temporary HOME.

source "$(dirname "$0")/lib.sh"

readonly UNINSTALL=$REPO_DIR/uninstall.sh
readonly ALL_PACKAGES='aerospace sketchybar claude swipeaerospace ghostty nvim btop hammerspoon'

# Links every package with the real stow, as a finished install would leave them.
link_everything() {
  use_real_stow
  # shellcheck disable=SC2086
  run_in_sandbox stow --dir="$REPO_DIR" --target="$HOME_DIR" $ALL_PACKAGES
}

# Makes every brew, defaults and process query report that nothing is left to remove.
simulate_already_removed() {
  stub brew 1
  stub defaults 1
  stub pgrep 1
  stub pkill 1
  stub killall 1
}

removes_codex_hooks() {
  mkdir -p "$HOME_DIR/.codex"
  printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"$HOME/.claude/claude-waiting.sh wait codex"}]}]}}' > "$HOME_DIR/.codex/hooks.json"
  run_in_sandbox PATH="$STUB_DIR:/usr/bin:/bin:/opt/homebrew/bin" "$UNINSTALL" >/dev/null
  if grep -q claude-waiting.sh "$HOME_DIR/.codex/hooks.json"; then fail 'Codex hooks left behind'; fi
}

unlinks_opencode_plugin() {
  use_real_stow
  mkdir -p "$HOME_DIR/.config/opencode/plugins"
  run_in_sandbox stow --dir="$REPO_DIR" --target="$HOME_DIR" opencode
  run_in_sandbox "$UNINSTALL" >/dev/null
  [ ! -e "$HOME_DIR/.config/opencode/plugins/omv-agent-state.js" ] || fail 'plugin left linked'
}

removes_theme_files() {
  mkdir -p "$HOME_DIR/.local/state/omv/theme" "$HOME_DIR/.local/share/omv/themes/nord"
  run_in_sandbox "$UNINSTALL" >/dev/null
  [ ! -e "$HOME_DIR/.local/state/omv/theme" ] && [ ! -e "$HOME_DIR/.local/share/omv/themes" ] || fail 'theme files left behind'
}

unstows_only_this_setup() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called "^stow --dir=$REPO_DIR --target=$HOME_DIR -D aerospace sketchybar claude swipeaerospace$"
}

keeps_older_tool_links() {
  link_everything
  run_in_sandbox "$UNINSTALL" >/dev/null
  local link
  for link in .config/ghostty .config/nvim .config/btop .hammerspoon; do
    [ -L "$HOME_DIR/$link" ] || fail "link was removed: $link"
  done
}

removes_this_setups_links() {
  link_everything
  run_in_sandbox "$UNINSTALL" >/dev/null
  local link
  for link in .config/aerospace .config/sketchybar; do
    if [ -e "$HOME_DIR/$link" ]; then
      fail "link was kept: $link"
    fi
  done
}

unstows_everything_with_all_flag() {
  run_in_sandbox "$UNINSTALL" --all >/dev/null
  assert_called "^stow --dir=$REPO_DIR --target=$HOME_DIR -D $ALL_PACKAGES$"
}

removes_usage_line() {
  mkdir -p "$HOME_DIR/.claude"
  printf 'input=$(cat)\nprintf x | "$HOME/.claude/bar-usage.sh" & # omv bar usage\n' > "$HOME_DIR/.claude/statusline-wrapper.sh"
  run_in_sandbox "$UNINSTALL" >/dev/null
  if grep -q bar-usage "$HOME_DIR/.claude/statusline-wrapper.sh"; then
    fail 'line is still in the wrapper'
  fi
}

removes_waiting_hooks() {
  mkdir -p "$HOME_DIR/.claude"
  printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"$HOME/.claude/claude-waiting.sh wait"}]}]}}' > "$HOME_DIR/.claude/settings.json"
  run_in_sandbox "$UNINSTALL" >/dev/null
  if grep -q claude-waiting.sh "$HOME_DIR/.claude/settings.json"; then
    fail 'hooks are still in the settings'
  fi
}

deletes_macos_settings() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^defaults delete NSGlobalDomain _HIHideMenuBar$'
  assert_called '^defaults delete com\.apple\.spaces spans-displays$'
}

removes_both_tools() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^brew uninstall --cask aerospace$'
  assert_called '^brew uninstall sketchybar$'
}

removes_swipe_cask() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^brew uninstall --cask swipeaerospace$'
}

untaps_swipe_tap() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^brew untap mediosz/tap$'
}

restores_builtin_trackpad_swipe() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^defaults delete com\.apple\.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture$'
}

restores_magic_trackpad_swipe() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^defaults delete com\.apple\.driver\.AppleBluetoothMultitouch\.trackpad TrackpadThreeFingerHorizSwipeGesture$'
}

restores_current_host_swipe() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^defaults -currentHost delete NSGlobalDomain com\.apple\.trackpad\.threeFingerHorizSwipeGesture$'
}

restores_window_animations() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^defaults delete NSGlobalDomain NSAutomaticWindowAnimationsEnabled$'
}

restores_window_dragging() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^defaults delete NSGlobalDomain NSWindowShouldDragOnGesture$'
}

stops_borders() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^pkill -x borders$'
}

skips_borders_when_not_running() {
  stub pgrep 1
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_not_called '^pkill -x borders$'
}

removes_borders() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^brew uninstall borders$'
}

quits_swipe_app() {
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called '^osascript -e tell application "SwipeAeroSpace" to quit$'
}

succeeds_when_already_removed() {
  simulate_already_removed
  assert_exit_zero run_in_sandbox "$UNINSTALL"
}

is_safe_to_rerun() {
  link_everything
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_exit_zero run_in_sandbox "$UNINSTALL"
}

rejects_unknown_flag() {
  assert_exit_nonzero run_in_sandbox "$UNINSTALL" --everything
}

changes_nothing_on_unknown_flag() {
  run_in_sandbox "$UNINSTALL" --everything >/dev/null 2>&1 || true
  [ ! -s "$CALL_LOG" ] || fail "made calls: $(cat "$CALL_LOG")"
}

keeps_real_file_at_stowed_path() {
  use_real_stow
  mkdir -p "$HOME_DIR/.config/aerospace"
  echo 'mine' > "$HOME_DIR/.config/aerospace/aerospace.toml"
  run_in_sandbox "$UNINSTALL" >/dev/null 2>&1 || true
  [ "$(cat "$HOME_DIR/.config/aerospace/aerospace.toml")" = 'mine' ] || fail 'real file was changed'
}

stops_keep_awake() {
  mkdir -p "$HOME_DIR/.local/state/omv"
  echo 4242 > "$HOME_DIR/.local/state/omv/keep-awake.pid"
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_called "^pkill -F $HOME_DIR/.local/state/omv/keep-awake.pid -x caffeinate$"
}

removes_keep_awake_pid() {
  mkdir -p "$HOME_DIR/.local/state/omv"
  echo 4242 > "$HOME_DIR/.local/state/omv/keep-awake.pid"
  run_in_sandbox "$UNINSTALL" >/dev/null
  if [ -e "$HOME_DIR/.local/state/omv/keep-awake.pid" ]; then
    fail 'pid file was kept'
  fi
}

skips_quit_when_not_running() {
  stub pgrep 1
  run_in_sandbox "$UNINSTALL" >/dev/null
  assert_not_called '^osascript'
}

run_case 'should unstow only aerospace, sketchybar, claude and swipeaerospace when run without flags' unstows_only_this_setup
run_case 'should keep the ghostty, nvim, btop and hammerspoon links when run without flags' keeps_older_tool_links
run_case 'should remove the aerospace and sketchybar links when run without flags' removes_this_setups_links
run_case 'should unstow all eight packages when run with --all' unstows_everything_with_all_flag
run_case 'should remove the usage line when uninstalling' removes_usage_line
run_case "should remove the waiting hooks from Claude's settings when uninstalling" removes_waiting_hooks
run_case 'should delete both macOS settings when they are set' deletes_macos_settings
run_case 'should remove aerospace and sketchybar when they are installed' removes_both_tools
run_case 'should remove the swipeaerospace cask when it is installed' removes_swipe_cask
run_case 'should untap mediosz/tap' untaps_swipe_tap
run_case 'should restore the three-finger swipe on the built-in trackpad' restores_builtin_trackpad_swipe
run_case 'should restore the three-finger swipe on the Magic Trackpad' restores_magic_trackpad_swipe
run_case 'should restore the three-finger swipe for the current host' restores_current_host_swipe
run_case 'should restore window-opening animations' restores_window_animations
run_case 'should restore normal window dragging' restores_window_dragging
run_case 'should stop borders when uninstalling' stops_borders
run_case 'should not stop borders when it is not running' skips_borders_when_not_running
run_case 'should remove borders when it is installed' removes_borders
run_case 'should quit SwipeAeroSpace when it is running' quits_swipe_app
run_case 'should succeed when the tools and settings are already gone' succeeds_when_already_removed
run_case 'should succeed when executed twice' is_safe_to_rerun
run_case 'should exit non-zero when given an unknown flag' rejects_unknown_flag
run_case 'should change nothing when given an unknown flag' changes_nothing_on_unknown_flag
run_case 'should leave a real file in place when it sits at a stowed path' keeps_real_file_at_stowed_path
run_case 'should not ask AeroSpace or SwipeAeroSpace to quit when they are not running' skips_quit_when_not_running
run_case 'should stop keep-awake when uninstalling' stops_keep_awake
run_case 'should remove the keep-awake pid file when uninstalling' removes_keep_awake_pid
run_case 'should remove the Codex hooks' removes_codex_hooks
run_case 'should unlink the OpenCode plugin' unlinks_opencode_plugin
run_case "should remove the theme's files" removes_theme_files
finish
