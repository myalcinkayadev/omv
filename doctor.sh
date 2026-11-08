#!/usr/bin/env bash
# Checks that the omv setup is healthy and says how to fix what isn't. Only reads: it
# changes no setting, link or process. Exits non-zero when a check fails.
# OMV_APPLICATIONS and OMV_FONT_DIRS replace /Applications and the font folders, for tests.

set -uo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_DIR
readonly PACKAGES=(aerospace sketchybar claude swipeaerospace ghostty nvim btop hammerspoon)
readonly APPLICATIONS=${OMV_APPLICATIONS:-/Applications}
readonly FONT_DIRS=${OMV_FONT_DIRS:-$HOME/Library/Fonts:/Library/Fonts}
readonly USAGE_MARKER='# omv bar usage'

problems=0

ok() {
  printf '  ✓ %s\n' "$1"
}

problem() {
  problems=$((problems + 1))
  if [ -n "${2:-}" ]; then
    printf '  ✗ %s — fix: %s\n' "$1" "$2"
  else
    printf '  ✗ %s\n' "$1"
  fi
}

section() {
  printf '\n%s\n' "$1"
}

check_tools() {
  section 'Tools'
  local tool fix
  for tool in aerospace sketchybar borders stow jq swiftc luajit; do
    case $tool in
      aerospace) fix='./install.sh' ;;
      sketchybar) fix='./install.sh' ;;
      borders) fix='brew install felixkratz/formulae/borders' ;;
      swiftc) fix='xcode-select --install' ;;
      *) fix="brew install $tool" ;;
    esac
    if command -v "$tool" >/dev/null 2>&1; then ok "$tool"; else problem "$tool is not installed" "$fix"; fi
  done
}

check_apps() {
  section 'Apps'
  local app cask
  for app in Hammerspoon Ghostty SwipeAeroSpace Zed Helium; do
    case $app in
      SwipeAeroSpace) cask='./install.sh' ;;
      Helium) cask='brew install --cask helium-browser' ;;
      *) cask="brew install --cask $(printf '%s' "$app" | tr '[:upper:]' '[:lower:]')" ;;
    esac
    if [ -d "$APPLICATIONS/$app.app" ]; then ok "$app"; else problem "$app is not installed" "$cask"; fi
  done
}

font_installed() {
  local dir
  local IFS=:
  for dir in $FONT_DIRS; do
    compgen -G "$dir/JetBrainsMonoNerdFont$1-*" >/dev/null && return 0
  done
  return 1
}

check_fonts() {
  section 'Font'
  local variant
  for variant in Mono Propo; do
    if font_installed "$variant"; then
      ok "JetBrainsMono Nerd Font $variant"
    else
      problem "JetBrainsMono Nerd Font $variant is not installed" 'brew install --cask font-jetbrains-mono-nerd-font'
    fi
  done
}

# A package is linked when each of its files, seen from $HOME, is the file in this repo.
# That holds for a link per file and for a whole folder linked at once.
check_links() {
  section 'Links'
  local package file relative missing broken directory link
  for package in "${PACKAGES[@]}"; do
    missing=()
    while IFS= read -r file; do
      relative=${file#"$REPO_DIR/$package/"}
      [ "$(realpath "$HOME/$relative" 2>/dev/null)" = "$(realpath "$file")" ] || missing+=("$relative")
    done < <(find "$REPO_DIR/$package" -type f ! -name '.DS_Store')
    if [ "${#missing[@]}" -eq 0 ]; then
      ok "$package"
    else
      problem "$package is not fully linked: ${missing[*]}" './install.sh'
    fi
  done
  # Links left behind by a file removed from the repo, like an old plugin.
  broken=()
  while IFS= read -r directory; do
    [ -d "$HOME/$directory" ] || continue
    while IFS= read -r link; do
      [[ $(readlink "$link") == *"$(basename "$REPO_DIR")/"* ]] && broken+=("${link#"$HOME/"}")
    done < <(find "$HOME/$directory" -maxdepth 1 -type l ! -exec test -e {} \; -print)
  done < <(for package in "${PACKAGES[@]}"; do
    find "$REPO_DIR/$package" -type f ! -name '.DS_Store' | sed "s|^$REPO_DIR/$package/||" | xargs -n1 dirname
  done | sort -u)
  for link in "${broken[@]+"${broken[@]}"}"; do
    problem "broken link: $link" "remove it, or run stow -R for its package"
  done
}

check_running() {
  section 'Running'
  local process
  for process in AeroSpace sketchybar borders Hammerspoon SwipeAeroSpace; do
    if pgrep -x "$process" >/dev/null 2>&1; then ok "$process"; else problem "$process is not running" "open it, or log out and back in"; fi
  done
  if [ "$(hs -c 'return type(omvToggleSystemMenu)' 2>/dev/null | tail -n 1)" = function ]; then
    ok 'Hammerspoon has the omv config loaded'
  else
    problem "Hammerspoon hasn't loaded the omv config" "reload Hammerspoon, then read its console"
  fi
}

check_setting() {
  local label=$1 domain=$2 key=$3 want=$4
  if [ "$(defaults read "$domain" "$key" 2>/dev/null)" = "$want" ]; then
    ok "$label"
  else
    problem "$label is off" './install.sh, then log out and back in'
  fi
}

check_settings() {
  section 'macOS settings'
  check_setting 'Hidden menu bar' NSGlobalDomain _HIHideMenuBar 1
  check_setting 'One Space across displays' com.apple.spaces spans-displays 1
  check_setting 'No window-opening animation' NSGlobalDomain NSAutomaticWindowAnimationsEnabled 0
  check_setting 'Ctrl+Cmd drag from anywhere' NSGlobalDomain NSWindowShouldDragOnGesture 1
  check_setting "macOS's three-finger swipe turned off" com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture 0
}

check_permissions() {
  section 'Permissions'
  if aerospace list-windows --all >/dev/null 2>&1; then
    ok 'AeroSpace can list windows (Accessibility)'
  else
    problem "AeroSpace can't list windows" 'allow AeroSpace in System Settings > Privacy & Security > Accessibility'
  fi
}

check_claude() {
  section 'Claude usage'
  if grep -qF "$USAGE_MARKER" "$HOME/.claude/statusline-wrapper.sh" 2>/dev/null; then
    ok 'usage line in ~/.claude/statusline-wrapper.sh'
  else
    problem "the Claude usage line isn't in ~/.claude/statusline-wrapper.sh" './claude-usage.sh add'
  fi
}

print_manual_checks() {
  cat <<'EOF'

Check by hand (macOS doesn't let a script read these)
  - Screen Recording for Hammerspoon, for the capture menu:
    System Settings > Privacy & Security > Screen & System Audio Recording
  - Calendar access for "omv agenda", for today's events:
    System Settings > Privacy & Security > Calendars
  - Location Services for Hammerspoon, for the weather and the Wi-Fi network's name:
    System Settings > Privacy & Security > Location Services
  - Microphone access for "omv meter", for the Sound card's level meter:
    System Settings > Privacy & Security > Microphone
  - Accessibility for SwipeAeroSpace, for three-finger swipes:
    System Settings > Privacy & Security > Accessibility
EOF
}

echo 'omv doctor'
check_tools
check_apps
check_fonts
check_links
check_running
check_settings
check_permissions
check_claude
print_manual_checks

echo
if [ "$problems" -eq 0 ]; then
  echo 'No problems found.'
  exit 0
fi
echo "$problems problem(s) found."
exit 1
