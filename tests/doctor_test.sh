#!/usr/bin/env bash
# Behavior of doctor.sh, against stubs, a temporary HOME and fake Applications and font folders.

source "$(dirname "$0")/lib.sh"

readonly DOCTOR=$REPO_DIR/doctor.sh
readonly ALL_PACKAGES='aerospace sketchybar claude swipeaerospace ghostty nvim btop hammerspoon'

# A finished install: every tool, app and font present, every package linked, every
# process running, every macOS setting applied, and the Claude usage line in place.
complete_setup() {
  local name
  for name in borders luajit gh; do stub "$name"; done
  cat > "$STUB_DIR/hs" <<STUB
#!/bin/sh
echo "hs \$*" >> "$CALL_LOG"
echo function
STUB
  # defaults answers from $SANDBOX/defaults, lines of "<domain> <key> <value>".
  cat > "$STUB_DIR/defaults" <<STUB
#!/bin/sh
echo "defaults \$*" >> "$CALL_LOG"
[ "\$1" = -currentHost ] && shift
[ "\$1" = read ] || exit 0
awk -v d="\$2" -v k="\$3" '\$1 == d && \$2 == k { print \$3; found = 1 } END { exit !found }' "$SANDBOX/defaults"
STUB
  chmod +x "$STUB_DIR/hs" "$STUB_DIR/defaults"
  cat > "$SANDBOX/defaults" <<'EOF'
NSGlobalDomain _HIHideMenuBar 1
com.apple.spaces spans-displays 1
NSGlobalDomain NSAutomaticWindowAnimationsEnabled 0
NSGlobalDomain NSWindowShouldDragOnGesture 1
com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture 0
EOF
  mkdir -p "$SANDBOX/Applications" "$SANDBOX/Fonts"
  for name in Hammerspoon Ghostty SwipeAeroSpace Zed Helium; do mkdir -p "$SANDBOX/Applications/$name.app"; done
  touch "$SANDBOX/Fonts/JetBrainsMonoNerdFontMono-Regular.ttf" "$SANDBOX/Fonts/JetBrainsMonoNerdFontPropo-Regular.ttf"
  use_real_stow
  mkdir -p "$HOME_DIR/.claude"
  # shellcheck disable=SC2086
  # --no-folding links file by file. A folded folder would be a link into this repo, and
  # removing a file "in the sandbox" would then delete the real one.
  run_in_sandbox stow --no-folding --dir="$REPO_DIR" --target="$HOME_DIR" $ALL_PACKAGES
  printf 'input=$(cat)\nprintf x | "$HOME/.claude/bar-usage.sh" & # omv bar usage\n' > "$HOME_DIR/.claude/statusline-wrapper.sh"
  printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"$HOME/.claude/claude-waiting.sh wait"}]}]}}' > "$HOME_DIR/.claude/settings.json"
  : > "$CALL_LOG"
}

doctor() {
  run_in_sandbox OMV_APPLICATIONS="$SANDBOX/Applications" OMV_FONT_DIRS="$SANDBOX/Fonts" "$DOCTOR"
}

report() {
  doctor 2>&1 || true
}

expect_report() {
  local output
  output=$(report)
  [[ $output == *"$1"* ]] || fail "expected '$1' in:"$'\n'"$output"
}

passes_complete_setup() {
  complete_setup
  assert_exit_zero doctor
}

reports_no_problems() {
  complete_setup
  expect_report 'No problems found'
}

fails_on_problem() {
  complete_setup
  remove_stub borders
  assert_exit_nonzero doctor
}

reports_logged_out_gh() {
  complete_setup
  stub gh 1
  expect_report 'gh is not logged in — fix: gh auth login'
}

skips_login_without_gh() {
  complete_setup
  remove_stub gh
  local output
  output=$(report)
  if [[ $output == *'not logged in'* ]]; then fail "reported a login without gh:"$'\n'"$output"; fi
}

names_missing_tool() {
  complete_setup
  remove_stub borders
  expect_report '✗ borders is not installed — fix: brew install felixkratz/formulae/borders'
}

names_missing_app() {
  complete_setup
  rm -rf "$SANDBOX/Applications/Helium.app"
  expect_report '✗ Helium is not installed'
}

names_missing_font() {
  complete_setup
  rm "$SANDBOX/Fonts/JetBrainsMonoNerdFontPropo-Regular.ttf"
  expect_report '✗ JetBrainsMono Nerd Font Propo is not installed'
}

# Removes a link, refusing anything that isn't one, so a test can't reach into the repo.
remove_link() {
  [ -L "$1" ] && [ ! -L "$(dirname "$1")" ] || fail "not a plain link, refusing to remove: $1"
  rm "$1"
}

reports_unlinked_file() {
  complete_setup
  remove_link "$HOME_DIR/.hammerspoon/pomo.lua"
  expect_report '✗ hammerspoon is not fully linked: .hammerspoon/pomo.lua — fix: ./install.sh'
}

reports_broken_link() {
  complete_setup
  [ ! -L "$HOME_DIR/.hammerspoon" ] || fail '.hammerspoon is a link into the repo'
  ln -s "../$(basename "$REPO_DIR")/hammerspoon/.hammerspoon/gone.lua" "$HOME_DIR/.hammerspoon/gone.lua"
  expect_report '✗ broken link: .hammerspoon/gone.lua'
}

reports_stopped_process() {
  complete_setup
  cat > "$STUB_DIR/pgrep" <<STUB
#!/bin/sh
for last; do :; done
[ "\$last" != borders ]
STUB
  chmod +x "$STUB_DIR/pgrep"
  expect_report '✗ borders is not running'
}

reports_missing_config() {
  complete_setup
  printf '#!/bin/sh\necho nil\n' > "$STUB_DIR/hs"
  expect_report "✗ Hammerspoon hasn't loaded the omv config"
}

reports_setting_off() {
  complete_setup
  sed -i '' 's/NSWindowShouldDragOnGesture 1/NSWindowShouldDragOnGesture 0/' "$SANDBOX/defaults"
  expect_report '✗ Ctrl+Cmd drag from anywhere is off — fix: ./install.sh'
}

reports_missing_accessibility() {
  complete_setup
  stub aerospace 1
  expect_report "✗ AeroSpace can't list windows"
}

reports_missing_usage_line() {
  complete_setup
  printf 'input=$(cat)\n' > "$HOME_DIR/.claude/statusline-wrapper.sh"
  expect_report "✗ the Claude usage line isn't in ~/.claude/statusline-wrapper.sh — fix: ./claude-usage.sh add"
}

reports_missing_waiting_hooks() {
  complete_setup
  printf '{}\n' > "$HOME_DIR/.claude/settings.json"
  expect_report "✗ the waiting hooks aren't in ~/.claude/settings.json — fix: ./claude-hooks.sh add"
}

lists_manual_checks() {
  complete_setup
  expect_report 'Check by hand'
}

lists_location_check() {
  complete_setup
  expect_report 'Location Services for Hammerspoon'
}

lists_microphone_check() {
  complete_setup
  expect_report 'Microphone access for "omv meter"'
}

changes_nothing() {
  complete_setup
  doctor >/dev/null 2>&1
  assert_not_called '^(defaults write|defaults delete|stow|brew install|pkill|killall|osascript)'
}

run_case 'should pass every check on a complete setup' passes_complete_setup
run_case 'should say there are no problems on a complete setup' reports_no_problems
run_case 'should exit non-zero when a check fails' fails_on_problem
run_case 'should name a missing tool and how to install it' names_missing_tool
run_case 'should name a missing app' names_missing_app
run_case 'should name a missing font' names_missing_font
run_case "should report when gh is not logged in" reports_logged_out_gh
run_case 'should skip the login check when gh is not installed' skips_login_without_gh
run_case "should report a package file that isn't linked" reports_unlinked_file
run_case 'should report a broken link' reports_broken_link
run_case "should report a tool that isn't running" reports_stopped_process
run_case "should report when Hammerspoon hasn't loaded the config" reports_missing_config
run_case "should report a macOS setting that's off" reports_setting_off
run_case "should report when AeroSpace can't list windows" reports_missing_accessibility
run_case 'should report a missing Claude usage line' reports_missing_usage_line
run_case "should report missing waiting hooks in Claude's settings" reports_missing_waiting_hooks
run_case 'should list the checks it cannot do as check by hand' lists_manual_checks
run_case 'should list Location for Hammerspoon as a check by hand' lists_location_check
run_case 'should list Microphone for the meter helper as a check by hand' lists_microphone_check
run_case 'should change nothing on the system' changes_nothing
finish
