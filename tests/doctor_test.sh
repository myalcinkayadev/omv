#!/usr/bin/env bash
# Behavior of doctor.sh, against stubs, a temporary HOME and fake Applications and font folders.

source "$(dirname "$0")/lib.sh"

readonly DOCTOR=$REPO_DIR/install/doctor.sh
readonly CONFIG_PACKAGES='sketchybar swipeaerospace ghostty nvim btop'

# A finished install: every tool, app and font present, every package linked, every
# process running, every macOS setting applied, and the Claude usage line in place.
complete_setup() {
  local name
  for name in borders gh mo m1ddc nightlight tmux; do stub "$name"; done
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
  # ps lists $SANDBOX/ps, lines of "<pid> <etime> <command>", then one bar per pid in
  # $SANDBOX/bars.
  cat > "$STUB_DIR/ps" <<STUB
#!/bin/sh
cat "$SANDBOX/ps"
while read -r pid; do echo "\$pid 1-00:00:00 /opt/homebrew/bin/sketchybar"; done < "$SANDBOX/bars"
STUB
  : > "$SANDBOX/ps"
  # pgrep finds every process. Like the real one, -x sketchybar matches the bars in
  # $SANDBOX/bars (one by default) and any sketchybar command, such as --query, in $SANDBOX/ps.
  cat > "$STUB_DIR/pgrep" <<STUB
#!/bin/sh
echo "pgrep \$*" >> "$CALL_LOG"
if [ "\$*" = "-x sketchybar" ]; then
  cat "$SANDBOX/bars"
  awk '{ name = \$3; sub(".*/", "", name); if (name == "sketchybar") print \$1 }' "$SANDBOX/ps"
fi
[ "\$*" = "-x Hammerspoon" ] && [ -f "$SANDBOX/no-hammerspoon" ] && exit 1
[ "\$*" = "-x SwipeAeroSpace" ] && [ -f "$SANDBOX/no-swipe" ] && exit 1
exit 0
STUB
  echo 500 > "$SANDBOX/bars"
  # pkill stops what it names: the bars are gone, and Hammerspoon is.
  cat > "$STUB_DIR/pkill" <<STUB
#!/bin/sh
echo "pkill \$*" >> "$CALL_LOG"
[ "\$*" = "-x sketchybar" ] && : > "$SANDBOX/bars"
[ "\$*" = "-x Hammerspoon" ] && touch "$SANDBOX/no-hammerspoon"
exit 0
STUB
  chmod +x "$STUB_DIR/pkill"
  # The bar answers --query bar, unless $SANDBOX/silent-bar says it has stopped answering.
  cat > "$STUB_DIR/sketchybar" <<STUB
#!/bin/sh
echo "sketchybar \$*" >> "$CALL_LOG"
[ "\$*" = "--query bar" ] && [ ! -f "$SANDBOX/silent-bar" ] && echo '{"hidden":"off"}'
exit 0
STUB
  chmod +x "$STUB_DIR/sketchybar"
  stub kill
  stub nohup
  chmod +x "$STUB_DIR/hs" "$STUB_DIR/defaults" "$STUB_DIR/ps" "$STUB_DIR/pgrep"
  cat > "$SANDBOX/defaults" <<EOF
NSGlobalDomain _HIHideMenuBar 1
com.apple.spaces spans-displays 1
NSGlobalDomain NSAutomaticWindowAnimationsEnabled 0
NSGlobalDomain NSWindowShouldDragOnGesture 1
com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture 0
org.hammerspoon.Hammerspoon MJConfigFile $REPO_DIR/config/hammerspoon/init.lua
EOF
  mkdir -p "$SANDBOX/Applications" "$SANDBOX/Fonts"
  for name in Hammerspoon Ghostty SwipeAeroSpace Zed Helium; do mkdir -p "$SANDBOX/Applications/$name.app"; done
  touch "$SANDBOX/Fonts/JetBrainsMonoNerdFontMono-Regular.ttf" "$SANDBOX/Fonts/JetBrainsMonoNerdFontPropo-Regular.ttf"
  use_real_stow
  mkdir -p "$HOME_DIR/.claude"
  # shellcheck disable=SC2086
  # --no-folding links file by file. A folded folder would be a link into this repo, and
  # removing a file "in the sandbox" would then delete the real one.
  run_in_sandbox stow --no-folding --dir="$REPO_DIR/config" --target="$HOME_DIR" $CONFIG_PACKAGES
  run_in_sandbox stow --no-folding --dir="$REPO_DIR/agents" --target="$HOME_DIR" claude
  printf 'input=$(cat)\nprintf x | "$HOME/.claude/bar-usage.sh" & # omv bar usage\n' > "$HOME_DIR/.claude/statusline-wrapper.sh"
  printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"$HOME/.claude/claude-waiting.sh wait"}]}]}}' > "$HOME_DIR/.claude/settings.json"
  mkdir -p "$SANDBOX/prefix/bin"
  ln -s "$REPO_DIR/bin/omv" "$SANDBOX/prefix/bin/omv"
  build_aerospace_here
  mkdir -p "$HOME_DIR/Applications/omv Setup.app/Contents/MacOS"
  touch "$HOME_DIR/Applications/omv Setup.app/Contents/MacOS/omv-setup"
  : > "$CALL_LOG"
}

# The stub hs answers at once, but in the suite's first seconds a busy machine can keep it
# from starting within the real 5, so tests give it 60. hang_hammerspoon sets 1, so a hang
# test is quick.
HS_LIMIT=60
# The same for the bar's answer; hang_bar sets 1.
BAR_LIMIT=60

doctor() {
  run_in_sandbox OMV_APPLICATIONS="$SANDBOX/Applications" OMV_FONT_DIRS="$SANDBOX/Fonts" OMV_HS_SECONDS="$HS_LIMIT" OMV_BAR_SECONDS="$BAR_LIMIT" OMV_BIN_DIR="$SANDBOX/prefix/bin" "$DOCTOR" "$@"
}

report() {
  doctor "$@" 2>&1 || true
}

expect_report() {
  local output
  output=$(report)
  [[ $output == *"$1"* ]] || fail "expected '$1' in:"$'\n'"$output"
}

expect_no_report() {
  local output
  output=$(report)
  [[ $output != *"$1"* ]] || fail "didn't expect '$1' in:"$'\n'"$output"
}

hang_hammerspoon() {
  printf '#!/bin/sh\necho "hs $*" >> "%s"\nexec sleep 120\n' "$CALL_LOG" > "$STUB_DIR/hs"
  HS_LIMIT=1
}

stuck_call() {
  printf '%s\n' "$1" >> "$SANDBOX/ps"
}

reports_hanging_hammerspoon() {
  complete_setup
  hang_hammerspoon
  local started=$SECONDS
  expect_report "✗ Hammerspoon isn't answering — fix: omv doctor --fix"
  # Well under the stub's 120s, with room for a doctor run slowed by a busy machine.
  [ $((SECONDS - started)) -le 90 ] || fail "took $((SECONDS - started))s"
}

reports_stuck_call() {
  complete_setup
  stuck_call '4242 01:01 hs -c omvRedrawBar()'
  expect_report '✗ 1 stuck hs call — fix: omv doctor --fix'
}

reads_age_in_days() {
  complete_setup
  stuck_call '4242 1-02:03:04 hs -c x'
  expect_report '✗ 1 stuck hs call'
}

reads_age_in_hours() {
  complete_setup
  stuck_call '4242 02:03:04 hs -c x'
  expect_report '✗ 1 stuck hs call'
}

ignores_young_call() {
  complete_setup
  stuck_call '4242 00:59 hs -c x'
  expect_no_report '✗ 1 stuck hs call'
}

ignores_hs_by_hand() {
  complete_setup
  stuck_call '4242 05:00 hs'
  expect_no_report '✗ 1 stuck hs call'
}

reports_two_bars() {
  complete_setup
  printf '500\n501\n' > "$SANDBOX/bars"
  expect_report '✗ 2 SketchyBars are running — fix: omv doctor --fix'
}

reports_silent_bar() {
  complete_setup
  touch "$SANDBOX/silent-bar"
  expect_report "✗ SketchyBar isn't answering — fix: omv doctor --fix"
}

hang_bar() {
  printf '#!/bin/sh\necho "sketchybar $*" >> "%s"\nexec sleep 120\n' "$CALL_LOG" > "$STUB_DIR/sketchybar"
  BAR_LIMIT=1
}

reports_hanging_bar() {
  complete_setup
  hang_bar
  local started=$SECONDS
  expect_report "✗ SketchyBar isn't answering — fix: omv doctor --fix"
  [ $((SECONDS - started)) -le 90 ] || fail "took $((SECONDS - started))s"
}

passes_answering_bar() {
  complete_setup
  expect_report '✓ one SketchyBar'
}

fix_restarts_silent_bar() {
  complete_setup
  touch "$SANDBOX/silent-bar"
  [[ $(report --fix) == *'→ restarted SketchyBar'* ]] || fail 'no restarted line'
  assert_called '^pkill -x sketchybar$'
}

# borders runs with its colours as arguments; the oldest of two was left by an AeroSpace
# that has since restarted.
two_borders() {
  stuck_call '600 3-00:00:00 borders active_color=0xff8d8d8d width=2.0'
  stuck_call '601 01:05:00 /opt/homebrew/bin/borders active_color=0xff8d8d8d width=2.0'
}

reports_two_borders() {
  complete_setup
  two_borders
  expect_report '✗ 2 borders are running — fix: omv doctor --fix'
}

passes_one_borders() {
  complete_setup
  stuck_call '601 01:05:00 borders active_color=0xff8d8d8d width=2.0'
  expect_report '✓ one borders'
}

fix_stops_older_borders() {
  complete_setup
  two_borders
  [[ $(report --fix) == *'→ stopped 1 extra borders'* ]] || fail 'no stopped line'
  assert_called '^kill 600$'
}

fix_keeps_newest_borders() {
  complete_setup
  two_borders
  report --fix >/dev/null
  assert_not_called '^kill .*601'
}

fix_kills_stuck_calls() {
  complete_setup
  stuck_call '4242 01:01 hs -c x'
  report --fix >/dev/null
  assert_called '^kill 4242$'
}

fix_says_killed() {
  complete_setup
  stuck_call '4242 01:01 hs -c x'
  [[ $(report --fix) == *'→ killed 1 stuck hs call'* ]] || fail 'no killed line'
}

fix_stops_bars() {
  complete_setup
  printf '500\n501\n' > "$SANDBOX/bars"
  report --fix >/dev/null
  assert_called '^pkill -x sketchybar$'
}

fix_starts_one_bar() {
  complete_setup
  printf '500\n501\n' > "$SANDBOX/bars"
  [[ $(report --fix) == *'→ restarted SketchyBar'* ]] || fail 'no restarted line'
  [ "$(grep -c '^nohup .*/sketchybar/start.sh$' "$CALL_LOG")" = 1 ] || fail 'expected one start through start.sh'
}

fix_reopens_hammerspoon() {
  complete_setup
  hang_hammerspoon
  [[ $(report --fix) == *'→ reopened Hammerspoon'* ]] || fail 'no reopened line'
  assert_called '^pkill -x Hammerspoon$'
  assert_called '^open -a Hammerspoon$'
}

fix_leaves_hammerspoon() {
  complete_setup
  report --fix >/dev/null
  assert_not_called '^(pkill|open).*Hammerspoon'
}

lists_disk_card_with_full_disk_access() {
  complete_setup
  expect_report 'Full Disk Access for Hammerspoon, to show Do Not Disturb in the bar and let the Disk card'
}

fix_changes_nothing() {
  complete_setup
  doctor --fix >/dev/null 2>&1 || fail 'expected exit 0'
  assert_not_called '^(kill|pkill|nohup|open)'
}

fix_starts_no_bar() {
  complete_setup
  : > "$SANDBOX/bars"
  report --fix >/dev/null
  assert_not_called '^nohup'
}

fix_opens_no_hammerspoon() {
  complete_setup
  hang_hammerspoon
  touch "$SANDBOX/no-hammerspoon"
  report --fix >/dev/null
  assert_not_called '^open -a Hammerspoon'
}

fix_opens_swipeaerospace() {
  complete_setup
  touch "$SANDBOX/no-swipe"
  report --fix >/dev/null
  assert_called '^open -a SwipeAeroSpace$'
}

fix_says_opened_swipeaerospace() {
  complete_setup
  touch "$SANDBOX/no-swipe"
  [[ $(report --fix) == *'→ opened SwipeAeroSpace'* ]] || fail 'no opened line'
}

fix_opens_no_missing_swipeaerospace() {
  complete_setup
  touch "$SANDBOX/no-swipe"
  rmdir "$SANDBOX/Applications/SwipeAeroSpace.app"
  report --fix >/dev/null
  assert_not_called '^open -a SwipeAeroSpace'
}


# The aerospace.toml omv builds, with the user file there is, as omv reload would write it.
build_aerospace_here() {
  mkdir -p "$HOME_DIR/.config/aerospace"
  luajit "$REPO_DIR/install/aerospace_merge.lua" "$REPO_DIR/config/aerospace/.config/aerospace/aerospace.toml" \
    "$HOME_DIR/.config/omv/aerospace.toml" "$HOME_DIR/.config/omv/workspaces" "$HOME_DIR/.local/state/omv/aerospace-screens.toml" \
    > "$HOME_DIR/.config/aerospace/aerospace.toml"
}

accepts_built_aerospace() {
  complete_setup
  expect_report '✓ aerospace.toml is built from omv and your settings'
}

reports_outdated_aerospace() {
  complete_setup
  mkdir -p "$HOME_DIR/.config/omv"
  printf '[gaps]\ninner.horizontal = 2\n' > "$HOME_DIR/.config/omv/aerospace.toml"
  expect_report '✗ aerospace.toml is out of date — fix: omv reload'
}

reports_foreign_aerospace() {
  complete_setup
  echo 'mine' > "$HOME_DIR/.config/aerospace/aerospace.toml"
  expect_report "✗ aerospace.toml isn't omv's — fix: omv reload"
}

reports_unreadable_user_aerospace() {
  complete_setup
  mkdir -p "$HOME_DIR/.config/omv"
  printf '[gaps\n' > "$HOME_DIR/.config/omv/aerospace.toml"
  expect_report '✗ ~/.config/omv/aerospace.toml line 1:'
}

reports_an_old_displays_file() {
  complete_setup
  mkdir -p "$HOME_DIR/.config/omv"
  printf '[desk]\nwhen = DELL\n' > "$HOME_DIR/.config/omv/displays"
  expect_report "✗ ~/.config/omv/displays isn't read any more"
}

skips_missing_old_profile_files() {
  complete_setup
  expect_no_report "isn't read any more"
}

reports_broken_workspaces_file() {
  complete_setup
  mkdir -p "$HOME_DIR/.config/omv"
  printf '[workspace 1]\n[workspace 12]\n' > "$HOME_DIR/.config/omv/workspaces"
  expect_report '✗ ~/.config/omv/workspaces line 2: a workspace is a number from 1 to 9 — fix: edit it'
}

passes_good_workspaces_file() {
  complete_setup
  mkdir -p "$HOME_DIR/.config/omv"
  printf '[workspace 1]\n[workspace 8]\non = screen 2\n[screen laptop]\ngaps = 4\n' > "$HOME_DIR/.config/omv/workspaces"
  expect_report '✓ ~/.config/omv/workspaces'
}

skips_missing_workspaces_file() {
  complete_setup
  expect_no_report 'omv/workspaces'
}

reports_linked_aerospace_folder() {
  complete_setup
  rm -rf "$HOME_DIR/.config/aerospace"
  ln -s "$REPO_DIR/config/aerospace/.config/aerospace" "$HOME_DIR/.config/aerospace"
  expect_report '✗ ~/.config/aerospace is still a link — fix: omv update'
}

reports_hammerspoon_config() {
  complete_setup
  sed -i '' '/MJConfigFile/d' "$SANDBOX/defaults"
  expect_report "✗ Hammerspoon doesn't load omv's config — fix: omv install"
}

accepts_hammerspoon_config() {
  complete_setup
  expect_report "✓ Hammerspoon loads omv's config"
}

refuses_unknown_argument() {
  complete_setup
  local status=0 errors
  errors=$(doctor --fxi 2>&1 >/dev/null) || status=$?
  [ "$status" = 2 ] || fail "expected exit 2, got $status"
  [[ $errors == *'usage: omv doctor [--fix]'* ]] || fail "expected usage, got: $errors"
}

counts_only_bars() {
  complete_setup
  stuck_call '502 00:30 sketchybar --query bar'
  expect_no_report 'SketchyBars are running'
}

reports_missing_hs() {
  complete_setup
  rm "$STUB_DIR/hs"
  expect_report "✗ the hs command isn't installed — fix: reload Hammerspoon"
}

fix_keeps_hammerspoon_without_hs() {
  complete_setup
  rm "$STUB_DIR/hs"
  report --fix >/dev/null
  assert_not_called '^pkill -x Hammerspoon'
}

skips_answer_when_not_running() {
  complete_setup
  hang_hammerspoon
  touch "$SANDBOX/no-hammerspoon"
  expect_no_report "isn't answering"
}

# Hammerspoon busy with something slow: the first question times out, the next is answered.
# Hammerspoon gives no answer the first time and answers the second. An empty answer counts the
# same as one that never came, so the first call returns at once: a hang until HS_LIMIT raced the
# stub's own start under a busy test run. reports_hanging_hammerspoon covers the hang.
fix_waits_for_busy_hammerspoon() {
  complete_setup
  printf '#!/bin/sh\n[ -f "%s/asked" ] && { echo function; exit 0; }\ntouch "%s/asked"\n' "$SANDBOX" "$SANDBOX" > "$STUB_DIR/hs"
  report --fix >/dev/null
  assert_not_called '^pkill -x Hammerspoon'
}

# kill stops what it's told to, unless the pid is listed in $SANDBOX/stubborn: then only -9 does.
stub_kill() {
  cat > "$STUB_DIR/kill" <<STUB
#!/bin/sh
echo "kill \$*" >> "$CALL_LOG"
force=0
[ "\$1" = -9 ] && { force=1; shift; }
for pid in "\$@"; do
  if [ "\$force" = 1 ] || ! grep -qx "\$pid" "$SANDBOX/stubborn" 2>/dev/null; then
    grep -v "^\$pid " "$SANDBOX/ps" > "$SANDBOX/ps.new"; mv "$SANDBOX/ps.new" "$SANDBOX/ps"
  fi
done
STUB
  chmod +x "$STUB_DIR/kill"
}

fix_force_kills_stubborn_call() {
  complete_setup
  stub_kill
  stuck_call '4242 01:01 hs -c x'
  echo 4242 > "$SANDBOX/stubborn"
  report --fix >/dev/null
  assert_called '^kill -9 4242$'
}

fix_spares_stopped_call() {
  complete_setup
  stub_kill
  stuck_call '4242 01:01 hs -c x'
  report --fix >/dev/null
  assert_not_called '^kill -9'
}

fix_force_kills_stubborn_bar() {
  complete_setup
  printf '500\n501\n' > "$SANDBOX/bars"
  # The bars outlive a plain pkill; only -9 stops them.
  cat > "$STUB_DIR/pkill" <<STUB
#!/bin/sh
echo "pkill \$*" >> "$CALL_LOG"
[ "\$*" = "-9 -x sketchybar" ] && : > "$SANDBOX/bars"
exit 0
STUB
  report --fix >/dev/null
  assert_called '^pkill -9 -x sketchybar$'
}

fix_says_nothing_to_fix() {
  complete_setup
  [[ $(report --fix) == *$'Fixing\n  ✓ nothing to fix'* ]] || fail 'expected nothing to fix under Fixing'
}

accepts_omv_link_by_another_path() {
  complete_setup
  ln -sfn "$REPO_DIR/bin/../bin/omv" "$SANDBOX/prefix/bin/omv"
  expect_report '✓ omv command'
}

points_manual_checks_to_permissions_card() {
  complete_setup
  expect_report 'or open Permissions in the system menu (Option+Escape)'
}

reports_missing_setup_app() {
  complete_setup
  rm -rf "$HOME_DIR/Applications/omv Setup.app"
  expect_report "✗ omv Setup isn't built — fix: omv doctor --fix"
}

# swiftc "builds" by writing the file after -o, as the real one would.
fix_builds_setup_app() {
  complete_setup
  rm -rf "$HOME_DIR/Applications/omv Setup.app"
  cat > "$STUB_DIR/swiftc" <<STUB
#!/bin/sh
while [ "\$#" -gt 0 ]; do [ "\$1" = -o ] && { printf '#!/bin/sh\\n' > "\$2"; chmod +x "\$2"; }; shift; done
STUB
  chmod +x "$STUB_DIR/swiftc"
  stub codesign
  [[ $(report --fix) == *'→ built omv Setup'* ]] || fail 'no built line'
  [ -x "$HOME_DIR/Applications/omv Setup.app/Contents/MacOS/omv-setup" ] || fail 'not built'
}

reports_missing_homebrew() {
  complete_setup
  remove_stub brew
  local output
  output=$(run_in_sandbox OMV_APPLICATIONS="$SANDBOX/Applications" OMV_FONT_DIRS="$SANDBOX/Fonts" OMV_HS_SECONDS="$HS_LIMIT" OMV_BREW_PATHS="$SANDBOX/none/brew" "$DOCTOR" 2>&1 || true)
  [[ $output == *"✗ Homebrew isn't installed — fix: install it from https://brew.sh"* ]] || fail "missing report in: $output"
}

finds_homebrew_off_path() {
  complete_setup
  remove_stub brew
  mkdir -p "$SANDBOX/homebrew/bin"
  printf '#!/bin/sh\necho "%s"\n' "$SANDBOX/homebrew" > "$SANDBOX/homebrew/bin/brew"
  chmod +x "$SANDBOX/homebrew/bin/brew"
  ln -s "$REPO_DIR/bin/omv" "$SANDBOX/homebrew/bin/omv"
  local output
  output=$(run_in_sandbox OMV_APPLICATIONS="$SANDBOX/Applications" OMV_FONT_DIRS="$SANDBOX/Fonts" OMV_HS_SECONDS="$HS_LIMIT" OMV_BREW_PATHS="$SANDBOX/none/brew:$SANDBOX/homebrew/bin/brew" "$DOCTOR" 2>&1 || true)
  [[ $output == *'✓ omv command'* ]] || fail "omv command not found in: $output"
}

reports_missing_omv() {
  complete_setup
  rm "$SANDBOX/prefix/bin/omv"
  expect_report "✗ the omv command isn't linked — fix: omv install"
}

kills_nothing_without_fix() {
  complete_setup
  stuck_call '4242 01:01 hs -c x'
  printf '500\n501\n' > "$SANDBOX/bars"
  doctor >/dev/null 2>&1 || true
  assert_not_called '^(kill|pkill|nohup|open)'
}

reports_missing_codex_hooks() {
  complete_setup
  mkdir -p "$HOME_DIR/.codex"
  expect_report "✗ the Codex hooks aren't in ~/.codex/hooks.json — fix: agents/codex-hooks.sh add"
}

reports_codex_hooks() {
  complete_setup
  mkdir -p "$HOME_DIR/.codex"
  printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"command":"$HOME/.claude/claude-waiting.sh wait codex"}]}]}}' > "$HOME_DIR/.codex/hooks.json"
  expect_report 'Codex hooks in ~/.codex/hooks.json'
}

reports_missing_opencode_plugin() {
  complete_setup
  mkdir -p "$HOME_DIR/.config/opencode"
  expect_report "✗ the OpenCode plugin isn't linked — fix: omv install"
}

skips_agents_not_set_up() {
  complete_setup
  local output
  output=$(report)
  [[ $output != *"Other agents"* ]] || fail "listed other agents in:"$'\n'"$output"
}

lists_bluetooth_check() {
  complete_setup
  expect_report 'Bluetooth for Hammerspoon, for the Bluetooth card'
}

passes_complete_setup() {
  complete_setup
  doctor > "$SANDBOX/report" 2>&1 || fail "$(grep '✗' "$SANDBOX/report")"
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

names_missing_mole() {
  complete_setup
  remove_stub mo
  expect_report '✗ mo is not installed — fix: brew install mole'
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
  remove_link "$HOME_DIR/.config/sketchybar/plugins/clock.sh"
  expect_report '✗ sketchybar is not fully linked: .config/sketchybar/plugins/clock.sh — fix: omv install'
}

reports_broken_link() {
  complete_setup
  [ ! -L "$HOME_DIR/.config/sketchybar/plugins" ] || fail 'the plugins folder is a link into the repo'
  ln -s "../../../$(basename "$REPO_DIR")/config/sketchybar/.config/sketchybar/plugins/gone.sh" "$HOME_DIR/.config/sketchybar/plugins/gone.sh"
  expect_report '✗ broken link: .config/sketchybar/plugins/gone.sh'
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
  expect_report '✗ Ctrl+Cmd drag from anywhere is off — fix: omv install'
}

reports_missing_accessibility() {
  complete_setup
  stub aerospace 1
  expect_report "✗ AeroSpace can't list windows"
}

reports_missing_usage_line() {
  complete_setup
  printf 'input=$(cat)\n' > "$HOME_DIR/.claude/statusline-wrapper.sh"
  expect_report "✗ the Claude usage line isn't in ~/.claude/statusline-wrapper.sh — fix: agents/claude-usage.sh add"
}

reports_missing_waiting_hooks() {
  complete_setup
  printf '{}\n' > "$HOME_DIR/.claude/settings.json"
  expect_report "✗ the waiting hooks aren't in ~/.claude/settings.json — fix: agents/claude-hooks.sh add"
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
run_case "should flag Hammerspoon when hs hangs" reports_hanging_hammerspoon
run_case 'should flag a stuck hs call when one runs over 60s' reports_stuck_call
run_case "should read a stuck call's age in days" reads_age_in_days
run_case "should read a stuck call's age in hours" reads_age_in_hours
run_case 'should ignore an hs call under 60s old' ignores_young_call
run_case "should ignore an hs that isn't a -c call" ignores_hs_by_hand
run_case 'should flag two bars when two run' reports_two_bars
run_case 'should flag two borders when two run' reports_two_borders
run_case 'should pass one borders when one runs' passes_one_borders
run_case 'should stop the older borders with --fix' fix_stops_older_borders
run_case 'should keep the newest borders with --fix' fix_keeps_newest_borders
run_case "should flag the bar when it doesn't answer" reports_silent_bar
run_case 'should pass the bar when it answers' passes_answering_bar
run_case 'should flag the bar when it hangs' reports_hanging_bar
run_case "should restart the bar with --fix when it doesn't answer" fix_restarts_silent_bar
run_case 'should kill nothing without --fix' kills_nothing_without_fix
run_case "should say Homebrew is missing when brew isn't found" reports_missing_homebrew
run_case "should find Homebrew in its usual folder when brew isn't on the PATH" finds_homebrew_off_path
run_case 'should point the manual checks to the Permissions card' points_manual_checks_to_permissions_card
run_case "should report the setup app when it isn't built" reports_missing_setup_app
run_case "should build the setup app when fixing and it isn't built" fix_builds_setup_app
run_case 'should accept a built aerospace.toml that is up to date' accepts_built_aerospace
run_case 'should report ~/.config/aerospace still linked' reports_linked_aerospace_folder
run_case 'should report an aerospace.toml that is out of date' reports_outdated_aerospace
run_case "should report an aerospace.toml omv didn't build" reports_foreign_aerospace
run_case "should report a user aerospace.toml it can't read" reports_unreadable_user_aerospace
run_case "should report a displays file that isn't read any more" reports_an_old_displays_file
run_case 'should say nothing about old profile files without them' skips_missing_old_profile_files
run_case 'should report a broken line in the workspaces file' reports_broken_workspaces_file
run_case 'should pass a workspaces file it can read' passes_good_workspaces_file
run_case 'should say nothing about workspaces without the file' skips_missing_workspaces_file
run_case "should report Hammerspoon not loading omv's config" reports_hammerspoon_config
run_case "should accept Hammerspoon loading omv's config" accepts_hammerspoon_config
run_case 'should open SwipeAeroSpace when --fix finds it not running' fix_opens_swipeaerospace
run_case 'should say SwipeAeroSpace was opened when --fix opens it' fix_says_opened_swipeaerospace
run_case "should not open SwipeAeroSpace when it isn't installed" fix_opens_no_missing_swipeaerospace
run_case "should report the omv command when it isn't linked" reports_missing_omv
run_case 'should accept an omv link that reaches this repo another way' accepts_omv_link_by_another_path
run_case 'should force-kill a stuck hs call that ignores the stop signal' fix_force_kills_stubborn_call
run_case 'should not force-kill a stuck hs call that stopped' fix_spares_stopped_call
run_case 'should force-kill a bar that ignores the stop signal' fix_force_kills_stubborn_bar
run_case "should say there's nothing to fix on a healthy setup" fix_says_nothing_to_fix
run_case 'should not count a sketchybar command as a bar' counts_only_bars
run_case 'should report a missing hs command' reports_missing_hs
run_case 'should not restart Hammerspoon with --fix when hs is missing' fix_keeps_hammerspoon_without_hs
run_case "should not say Hammerspoon isn't answering when it isn't running" skips_answer_when_not_running
run_case 'should leave a busy Hammerspoon alone with --fix when it answers on the second try' fix_waits_for_busy_hammerspoon
run_case 'should kill stuck hs calls with --fix' fix_kills_stuck_calls
run_case 'should say it killed the stuck calls with --fix' fix_says_killed
run_case 'should stop every bar with --fix when two run' fix_stops_bars
run_case 'should start one bar with --fix when two ran' fix_starts_one_bar
run_case "should reopen Hammerspoon with --fix when it doesn't answer" fix_reopens_hammerspoon
run_case 'should leave Hammerspoon alone with --fix when it answers' fix_leaves_hammerspoon
run_case 'should change nothing with --fix on a healthy setup' fix_changes_nothing
run_case 'should start no bar with --fix when none runs' fix_starts_no_bar
run_case "should not open Hammerspoon with --fix when it isn't running" fix_opens_no_hammerspoon
run_case 'should refuse an unknown argument' refuses_unknown_argument
run_case 'should say there are no problems on a complete setup' reports_no_problems
run_case 'should exit non-zero when a check fails' fails_on_problem
run_case 'should name a missing tool and how to install it' names_missing_tool
run_case 'should name a missing Mole and how to install it' names_missing_mole
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
run_case 'should name the Disk card when listing Full Disk Access' lists_disk_card_with_full_disk_access
run_case 'should list Location for Hammerspoon as a check by hand' lists_location_check
run_case 'should list Microphone for the meter helper as a check by hand' lists_microphone_check
run_case 'should change nothing on the system' changes_nothing
run_case "should report the Codex hooks missing when Codex is set up" reports_missing_codex_hooks
run_case 'should report the Codex hooks in place' reports_codex_hooks
run_case "should report the OpenCode plugin missing when OpenCode is set up" reports_missing_opencode_plugin
run_case 'should skip other agents when none is set up' skips_agents_not_set_up
run_case 'should list Bluetooth for Hammerspoon as a check by hand' lists_bluetooth_check
finish
