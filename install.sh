#!/usr/bin/env bash
# Installs AeroSpace and SketchyBar, links every config with Stow and applies the
# macOS settings. Safe to run again. uninstall.sh reverses it.

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_DIR
readonly TAPS=(nikitabobko/tap felixkratz/formulae)
readonly PACKAGES=(aerospace sketchybar ghostty nvim btop hammerspoon)

require_command() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "install.sh: $1 is required. Install it first." >&2
  exit 1
}

install_tools() {
  local tap
  for tap in "${TAPS[@]}"; do
    brew tap "$tap"
    brew trust --tap "$tap"
  done
  brew install --cask nikitabobko/tap/aerospace
  brew install felixkratz/formulae/sketchybar
}

link_configs() {
  stow --dir="$REPO_DIR" --target="$HOME" "${PACKAGES[@]}" && return 0
  echo "install.sh: stow could not link the configs. Move the files it named, then run this again." >&2
  exit 1
}

apply_macos_settings() {
  defaults write NSGlobalDomain _HIHideMenuBar -bool true
  defaults write com.apple.spaces spans-displays -bool true
  killall SystemUIServer || true
}

print_manual_steps() {
  cat <<'EOF'

Installed. These steps are yours:
  1. Open AeroSpace from Finder and grant Accessibility in System Settings.
  2. Log out and back in, so "Displays have separate Spaces" turns off.
  3. If the menu bar still shows, set System Settings > Menu Bar >
     "Automatically hide and show the menu bar" to Always.
  4. In System Settings > Displays > Arrange, leave each display a free bottom
     corner. AeroSpace hides windows there.
EOF
}

require_command brew
require_command stow
install_tools
link_configs
apply_macos_settings
print_manual_steps
