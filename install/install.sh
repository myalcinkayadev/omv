#!/usr/bin/env bash
# Usage: install.sh [--dry-run] [--no-apps]
# Installs everything in the Brewfile, and the apps in Brewfile.apps unless --no-apps, links
# every config with Stow and applies the macOS settings. --dry-run prints each step instead
# of running it. Safe to run again. uninstall.sh reverses it.

set -euo pipefail

# Physical, as bin/omv's: the Hammerspoon setting and link checks compare this path.
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
readonly REPO_DIR
readonly TAPS=(nikitabobko/tap felixkratz/formulae mediosz/tap smudge/smudge)
# shellcheck source=packages.sh
source "$REPO_DIR/install/packages.sh"
# shellcheck source=hammerspoon.sh
source "$REPO_DIR/install/hammerspoon.sh"
# shellcheck source=aerospace.sh
source "$REPO_DIR/install/aerospace.sh"

DRY_RUN=false
APPS=true
for argument in "$@"; do
  case $argument in
    --dry-run) DRY_RUN=true ;;
    --no-apps) APPS=false ;;
    *)
      echo "usage: install.sh [--dry-run] [--no-apps]" >&2
      exit 2
      ;;
  esac
done
readonly DRY_RUN APPS

# Runs a step, or with --dry-run only says what it would run.
step() {
  if $DRY_RUN; then
    echo "would run: $*"
    return 0
  fi
  "$@"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "install.sh: $1 is required. Install it first." >&2
  exit 1
}

install_tools() {
  local tap
  # Homebrew refuses to install from a third-party tap until it's trusted.
  for tap in "${TAPS[@]}"; do
    step brew tap "$tap"
    step brew trust --tap "$tap"
  done
  step brew bundle --file="$REPO_DIR/Brewfile"
  if $APPS; then step brew bundle --file="$REPO_DIR/Brewfile.apps"; fi
}

link_configs() {
  # Stow would otherwise replace a missing ~/.claude with a link into this repo.
  step mkdir -p "$HOME/.claude"
  step stow --dir="$REPO_DIR/config" --target="$HOME" "${CONFIG_PACKAGES[@]}" \
    && step stow --dir="$REPO_DIR/agents" --target="$HOME" "${AGENT_PACKAGES[@]}" && return 0
  echo "install.sh: stow could not link the configs. Move the files it named, then run this again." >&2
  exit 1
}

# omv goes where Homebrew puts its commands, which is on PATH. OMV_BIN_DIR replaces that
# folder, for tests. Without either, omv is still there as bin/omv in this repo.
link_omv() {
  local folder=${OMV_BIN_DIR:-}
  if [ -z "$folder" ] && $DRY_RUN; then
    echo "would run: ln -sfn $REPO_DIR/bin/omv \$(brew --prefix)/bin/omv"
    return 0
  fi
  if [ -z "$folder" ]; then
    folder=$(brew --prefix 2>/dev/null || true)
    [ -n "$folder" ] && folder=$folder/bin
  fi
  if [ -z "$folder" ]; then
    echo "install.sh: couldn't find Homebrew's folder, so omv isn't on PATH; run $REPO_DIR/bin/omv" >&2
    return 0
  fi
  step mkdir -p "$folder"
  step ln -sfn "$REPO_DIR/bin/omv" "$folder/omv"
}

# Codex, OpenCode and pi report their sessions to the bar too, each only when it's set up
# here. Their plugin folders are made first, so Stow links the file, not the folder.
link_agents() {
  if [ -d "$HOME/.codex" ]; then step "$REPO_DIR/agents/codex-hooks.sh" add; fi
  if [ -d "$HOME/.config/opencode" ]; then
    step mkdir -p "$HOME/.config/opencode/plugins"
    step stow --dir="$REPO_DIR/agents" --target="$HOME" opencode
  fi
  if [ -d "$HOME/.pi/agent" ]; then
    step mkdir -p "$HOME/.pi/agent/extensions"
    step stow --dir="$REPO_DIR/agents" --target="$HOME" pi
  fi
}

apply_macos_settings() {
  step defaults write NSGlobalDomain _HIHideMenuBar -bool true
  step defaults write com.apple.spaces spans-displays -bool true
  # New windows appear at once instead of zooming in.
  step defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
  # Ctrl+Cmd+drag moves a window by any part of it, which helps with floating windows.
  step defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true
  # SwipeAeroSpace owns the three-finger swipe, so macOS's own would fire a second action.
  step defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture -int 0
  step defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture -int 0
  step defaults -currentHost write NSGlobalDomain com.apple.trackpad.threeFingerHorizSwipeGesture -int 0
  step killall SystemUIServer || true
}

print_manual_steps() {
  cat <<'EOF'

Installed. These steps are yours:
  1. Open AeroSpace from Finder and grant Accessibility in System Settings.
  2. Log out and back in, so "Displays have separate Spaces" and macOS's
     three-finger swipe turn off.
  3. If the menu bar still shows, set System Settings > Menu Bar >
     "Automatically hide and show the menu bar" to Always.
  4. In System Settings > Displays > Arrange, leave each display a free bottom
     corner. AeroSpace hides windows there.
  5. Open SwipeAeroSpace, grant Accessibility, and turn on Launch at Login in
     its Settings.

Then run omv doctor to check that everything is in place.
EOF
}

require_command brew
install_tools
# The Brewfile installs Stow, so it's only needed from here on.
$DRY_RUN || require_command stow
link_configs
if $DRY_RUN; then
  echo "would run: defaults write org.hammerspoon.Hammerspoon MJConfigFile $HAMMERSPOON_CONFIG"
  echo "would run: build ~/.config/aerospace/aerospace.toml"
else
  point_hammerspoon
  # A mistake in the user's file mustn't stop the install; the doctor names its line.
  build_aerospace || echo "install.sh: kept the old aerospace.toml; once the above is fixed, run omv reload" >&2
fi
link_omv
step "$REPO_DIR/agents/claude-usage.sh" add
step "$REPO_DIR/agents/claude-hooks.sh" add
link_agents
apply_macos_settings
$DRY_RUN || print_manual_steps
