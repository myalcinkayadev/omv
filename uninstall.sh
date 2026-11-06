#!/usr/bin/env bash
# Reverses install.sh. Anything already removed is skipped, so a failed step never
# stops the rest. By default, the older ghostty, nvim, btop and hammerspoon links
# stay; --all removes them too. The repo itself is never touched.

set -uo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_DIR
readonly TAPS=(nikitabobko/tap felixkratz/formulae)
readonly SETUP_PACKAGES=(aerospace sketchybar claude)
readonly OLDER_PACKAGES=(ghostty nvim btop hammerspoon)

packages=("${SETUP_PACKAGES[@]}")

parse_arguments() {
  [ "$#" -eq 0 ] && return 0
  if [ "$#" -eq 1 ] && [ "$1" = '--all' ]; then
    packages+=("${OLDER_PACKAGES[@]}")
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
  if pgrep -x sketchybar >/dev/null 2>&1; then
    pkill -x sketchybar
  fi
}

# Runs before unlinking, so the status line never calls a script that is already gone.
remove_claude_usage() {
  "$REPO_DIR/claude-usage.sh" remove
  rm -f "$HOME/.local/state/omv/claude-usage" "$HOME/.local/state/omv/claude-usage-resets-view"
}

unlink_configs() {
  if ! command -v stow >/dev/null 2>&1; then
    echo "uninstall.sh: stow is missing, so the config links were left in place." >&2
    return 0
  fi
  stow --dir="$REPO_DIR" --target="$HOME" -D "${packages[@]}"
}

reset_macos_settings() {
  defaults delete NSGlobalDomain _HIHideMenuBar 2>/dev/null
  defaults delete com.apple.spaces spans-displays 2>/dev/null
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
  local tap
  for tap in "${TAPS[@]}"; do
    brew untap "$tap" 2>/dev/null || echo "uninstall.sh: kept tap $tap; it is absent or still in use."
    brew untrust --tap "$tap" 2>/dev/null
  done
}

print_remaining_steps() {
  cat <<'EOF'

Removed. These steps are yours:
  1. Log out and back in, so "Displays have separate Spaces" returns to its default.
  2. If you hid the menu bar in System Settings > Menu Bar, change that setting back.
  3. Remove AeroSpace from System Settings > Privacy & Security > Accessibility.

Left in place: this repo, Homebrew's other packages, your fonts, ~/.config/omniwm
and ~/.config-backup.
EOF
}

parse_arguments "$@"
quit_apps
remove_claude_usage
unlink_configs
reset_macos_settings
remove_tools
print_remaining_steps
exit 0
