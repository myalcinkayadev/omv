#!/usr/bin/env bash
# Reverses install.sh. Anything already removed is skipped, so a failed step never
# stops the rest. By default, the older ghostty, nvim and btop links and Hammerspoon's
# setting that loads omv's config stay; --all removes them too. The repo itself is never touched.

set -uo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_DIR
# shellcheck source=packages.sh
source "$REPO_DIR/install/packages.sh"
# shellcheck source=hammerspoon.sh
source "$REPO_DIR/install/hammerspoon.sh"
# shellcheck source=aerospace.sh
source "$REPO_DIR/install/aerospace.sh"
readonly TAPS=(nikitabobko/tap felixkratz/formulae mediosz/tap)
readonly SETUP_PACKAGES=(sketchybar claude swipeaerospace)
readonly OLDER_PACKAGES=(ghostty nvim btop)

packages=("${SETUP_PACKAGES[@]}")
all=false

parse_arguments() {
  [ "$#" -eq 0 ] && return 0
  if [ "$#" -eq 1 ] && [ "$1" = '--all' ]; then
    packages+=("${OLDER_PACKAGES[@]}")
    all=true
    return 0
  fi
  echo "usage: uninstall.sh [--all]" >&2
  exit 2
}

# Quitting AeroSpace first brings back the windows it has hidden.
quit_apps() {
  if pgrep -x AeroSpace >/dev/null 2>&1; then
    osascript -e 'tell application "AeroSpace" to quit'
  fi
  if pgrep -x SwipeAeroSpace >/dev/null 2>&1; then
    osascript -e 'tell application "SwipeAeroSpace" to quit'
  fi
  if pgrep -x sketchybar >/dev/null 2>&1; then
    pkill -x sketchybar
  fi
  if pgrep -x borders >/dev/null 2>&1; then
    pkill -x borders
  fi
}

# Otherwise the saved caffeinate would keep the Mac awake after the bar is gone.
stop_keep_awake() {
  local pid_file=$HOME/.local/state/omv/keep-awake.pid
  [ -e "$pid_file" ] || return 0
  pkill -F "$pid_file" -x caffeinate
  rm -f "$pid_file"
}

# Runs before unlinking, so the status line never calls a script that is already gone.
remove_claude_usage() {
  "$REPO_DIR/agents/claude-usage.sh" remove
  "$REPO_DIR/agents/claude-hooks.sh" remove
  "$REPO_DIR/agents/codex-hooks.sh" remove
  rm -f "$HOME/.local/state/omv/claude-usage" "$HOME/.local/state/omv/claude-usage-resets-view"
  rm -rf "$HOME/.local/state/omv/claude-sessions" "$HOME/.local/state/omv/claude-waiting"
  # The chosen theme's colours and the themes fetched from Omarchy.
  rm -rf "$HOME/.local/state/omv/theme" "$HOME/.local/share/omv/themes"
}

unlink_configs() {
  if ! command -v stow >/dev/null 2>&1; then
    echo "uninstall.sh: stow is missing, so the config links were left in place." >&2
    return 0
  fi
  local package folder
  # One call per folder, each with the packages that live there.
  for folder in "$REPO_DIR/config" "$REPO_DIR/agents"; do
    local here=()
    for package in "${packages[@]}"; do
      if [ "$(package_dir "$package")" = "$folder" ]; then here+=("$package"); fi
    done
    if [ "${#here[@]}" -gt 0 ]; then stow --dir="$folder" --target="$HOME" -D "${here[@]}"; fi
  done
  # The other agents' plugins, linked only when that agent was set up.
  if [ -L "$HOME/.config/opencode/plugins/omv-agent-state.js" ]; then stow --dir="$REPO_DIR/agents" --target="$HOME" -D opencode; fi
  if [ -L "$HOME/.pi/agent/extensions/omv-agent-state.ts" ]; then stow --dir="$REPO_DIR/agents" --target="$HOME" -D pi; fi
}

# Only the file omv built: one the user wrote isn't ours to remove.
remove_built_aerospace() {
  if aerospace_built_by_omv; then rm "$AEROSPACE_BUILT"; fi
}

# Back to ~/.hammerspoon, only when the setting is omv's: another one isn't ours to remove.
forget_hammerspoon_config() {
  $all || return 0
  [ "$(hammerspoon_config)" = "$HAMMERSPOON_CONFIG" ] || return 0
  defaults delete org.hammerspoon.Hammerspoon MJConfigFile
}

# Only an omv that leads to this repo: another one isn't ours to remove.
remove_omv_command() {
  local folder=${OMV_BIN_DIR:-} link
  if [ -z "$folder" ]; then
    folder=$(brew --prefix 2>/dev/null || true)
    [ -n "$folder" ] && folder=$folder/bin
  fi
  [ -n "$folder" ] || return 0
  link=$folder/omv
  if [ -L "$link" ] && [ "$link" -ef "$REPO_DIR/bin/omv" ]; then rm "$link"; fi
}

reset_macos_settings() {
  defaults delete NSGlobalDomain _HIHideMenuBar 2>/dev/null
  defaults delete com.apple.spaces spans-displays 2>/dev/null
  defaults delete NSGlobalDomain NSAutomaticWindowAnimationsEnabled 2>/dev/null
  defaults delete NSGlobalDomain NSWindowShouldDragOnGesture 2>/dev/null
  defaults delete com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture 2>/dev/null
  defaults delete com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture 2>/dev/null
  defaults -currentHost delete NSGlobalDomain com.apple.trackpad.threeFingerHorizSwipeGesture 2>/dev/null
  killall SystemUIServer 2>/dev/null
}

# Removing the app also ends its start-at-login registration.
remove_tools() {
  command -v brew >/dev/null 2>&1 || return 0
  if brew list --cask aerospace >/dev/null 2>&1; then
    brew uninstall --cask aerospace
  fi
  if brew list sketchybar >/dev/null 2>&1; then
    brew uninstall sketchybar
  fi
  if brew list borders >/dev/null 2>&1; then
    brew uninstall borders
  fi
  if brew list --cask swipeaerospace >/dev/null 2>&1; then
    brew uninstall --cask swipeaerospace
  fi
  local tap
  for tap in "${TAPS[@]}"; do
    brew untap "$tap" 2>/dev/null || echo "uninstall.sh: kept tap $tap; it is absent or still in use."
    brew untrust --tap "$tap" 2>/dev/null
  done
}

print_remaining_steps() {
  cat <<'EOF'

Removed. These steps are yours:
  1. Log out and back in, so "Displays have separate Spaces" and the three-finger
     swipe return to their defaults.
  2. If you hid the menu bar in System Settings > Menu Bar, change that setting back.
  3. Remove AeroSpace and SwipeAeroSpace from System Settings > Privacy & Security >
     Accessibility.

Left in place: this repo, Homebrew's other packages, your fonts, ~/.config/omniwm
and ~/.config-backup.
EOF
}

parse_arguments "$@"
quit_apps
stop_keep_awake
remove_claude_usage
unlink_configs
remove_built_aerospace
forget_hammerspoon_config
remove_omv_command
reset_macos_settings
remove_tools
print_remaining_steps
exit 0
