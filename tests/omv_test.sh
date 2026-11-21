#!/usr/bin/env bash
# Behavior of bin/omv, the one command over install, update, doctor, flags and themes.
# It runs from a copy in a sandbox repo with stub scripts, so update never touches this repo.

source "$(dirname "$0")/lib.sh"

# A repo with the real omv, packages list and flag defaults, and stub install, uninstall and
# doctor scripts (in install/) that log their arguments. git answers from files: $SANDBOX/dirty (status),
# $SANDBOX/branch (main by default) and $SANDBOX/head (the commit).
make_repo() {
  # Physical, as bin/omv resolves its own path: /var is a link to /private/var.
  REPO=$(cd "$SANDBOX" && pwd -P)/repo
  mkdir -p "$REPO/bin" "$REPO/install" "$REPO/migrations" "$REPO/config/hammerspoon"
  cp "$REPO_DIR/bin/omv" "$REPO/bin/omv"
  cp -R "$REPO_DIR/install/." "$REPO/install/"
  mkdir -p "$REPO/config/aerospace/.config/aerospace"
  printf '[gaps]\ninner.horizontal = 10\n' > "$REPO/config/aerospace/.config/aerospace/aerospace.toml"
  cp "$REPO_DIR/config/hammerspoon/flags.lua" "$REPO/config/hammerspoon/flags.lua"
  mkdir -p "$REPO/config/sketchybar/.config/sketchybar"
  cp "$REPO_DIR/config/sketchybar/.config/sketchybar/flags.sh" "$REPO/config/sketchybar/.config/sketchybar/flags.sh"
  local script
  for script in install uninstall doctor; do
    printf '#!/bin/sh\necho "%s.sh $*" >> "%s"\nexit $(cat "%s/%s-exit" 2>/dev/null || echo 0)\n' \
      "$script" "$CALL_LOG" "$SANDBOX" "$script" > "$REPO/install/$script.sh"
    chmod +x "$REPO/install/$script.sh"
  done
  : > "$SANDBOX/dirty"
  echo main > "$SANDBOX/branch"
  echo aaa111 > "$SANDBOX/head"
  cat > "$STUB_DIR/git" <<STUB
#!/bin/sh
echo "git \$*" >> "$CALL_LOG"
[ "\$1" = -C ] && shift 2
case "\$*" in
  "status --porcelain") cat "$SANDBOX/dirty" ;;
  "rev-parse --abbrev-ref HEAD") cat "$SANDBOX/branch" ;;
  "rev-parse HEAD") cat "$SANDBOX/head" ;;
  "pull --ff-only")
    [ -f "$SANDBOX/pull-fails" ] && exit 1
    [ -f "$SANDBOX/up-to-date" ] || echo bbb222 > "$SANDBOX/head"
    [ -x "$SANDBOX/on-pull" ] && "$SANDBOX/on-pull"
    ;;
  "reset --hard "*) echo "\$3" > "$SANDBOX/head" ;;
  "log -1 --format=%h %cs") echo "\$(cat "$SANDBOX/head") 2026-11-15" ;;
esac
exit 0
STUB
  chmod +x "$STUB_DIR/git"
  stub hs
  answer_hammerspoon_config "$REPO/config/hammerspoon/init.lua"
}

# defaults answers $1 for Hammerspoon's config file, and logs every call.
answer_hammerspoon_config() {
  cat > "$STUB_DIR/defaults" <<STUB
#!/bin/sh
echo "defaults \$*" >> "$CALL_LOG"
[ "\$*" = "read org.hammerspoon.Hammerspoon MJConfigFile" ] && echo "$1"
exit 0
STUB
  chmod +x "$STUB_DIR/defaults"
}

# pgrep finds Hammerspoon, with a pid no process has, so the wait for it to quit ends at once.
run_hammerspoon() {
  printf '#!/bin/sh\necho "pgrep $*" >> "%s"\n[ "$*" = "-x Hammerspoon" ] && echo 999999\nexit 0\n' "$CALL_LOG" > "$STUB_DIR/pgrep"
  chmod +x "$STUB_DIR/pgrep"
}

omv() {
  run_in_sandbox "$REPO/bin/omv" "$@"
}

saved_commit() {
  cat "$HOME_DIR/.local/state/omv/update-from" 2>/dev/null
}

# A migration that logs its name, or fails when its name ends in -fails.
add_migration() {
  local exit_code=0
  [[ $1 == *-fails ]] && exit_code=1
  printf '#!/bin/sh\necho "migration %s" >> "%s"\nexit %s\n' "$1" "$CALL_LOG" "$exit_code" > "$REPO/migrations/$1.sh"
  chmod +x "$REPO/migrations/$1.sh"
}

# The number of the first call-log line matching $1, or nothing.
line_of() {
  grep -nE -m1 -e "$1" "$CALL_LOG" | cut -d: -f1
}

# Fails unless the first call matching $1 comes before the first matching $2.
assert_before() {
  local first second
  first=$(line_of "$1")
  second=$(line_of "$2")
  [ -n "$first" ] && [ -n "$second" ] && [ "$first" -lt "$second" ] \
    || fail "expected $1 before $2 in:"$'\n'"$(cat "$CALL_LOG")"
}

migrates_before_relinking() {
  make_repo
  add_migration 202601010000-a
  omv update >/dev/null
  assert_before '^migration ' '^stow '
}

relinks_before_installing_packages() {
  make_repo
  omv update >/dev/null
  assert_before '^stow ' '^brew bundle --no-upgrade'
}

migrates_before_installing() {
  make_repo
  add_migration 202601010000-a
  omv install --no-setup >/dev/null
  assert_before '^migration ' '^install\.sh'
}

shows_usage_without_command() {
  make_repo
  local status=0
  omv >/dev/null 2>&1 || status=$?
  [ "$status" = 2 ] || fail "expected exit 2, got $status"
}

shows_usage_for_unknown_command() {
  make_repo
  local status=0 errors
  errors=$(omv nope 2>&1 >/dev/null) || status=$?
  [ "$status" = 2 ] || fail "expected exit 2, got $status"
  [[ $errors == *'usage: omv'* ]] || fail "expected usage, got: $errors"
}

update_refuses_dirty_tree() {
  make_repo
  echo ' M README.md' > "$SANDBOX/dirty"
  assert_exit_nonzero omv update
  assert_not_called '^git .*pull'
}

update_refuses_other_branch() {
  make_repo
  echo feature > "$SANDBOX/branch"
  assert_exit_nonzero omv update
  assert_not_called '^git .*pull'
}

update_saves_commit() {
  make_repo
  omv update >/dev/null
  [ "$(saved_commit)" = aaa111 ] || fail "saved: $(saved_commit)"
}

update_pulls_fast_forward_only() {
  make_repo
  omv update >/dev/null
  assert_called '^git -C .* pull --ff-only$'
}

update_restows() {
  make_repo
  omv update >/dev/null
  assert_called '^stow .*--restow .*sketchybar'
}

update_reloads_hammerspoon() {
  make_repo
  omv update >/dev/null
  assert_called '^hs .*hs\.reload'
}

update_reloads_bar() {
  make_repo
  omv update >/dev/null
  assert_called '^sketchybar --reload$'
}

update_runs_doctor() {
  make_repo
  omv update >/dev/null
  assert_called '^doctor\.sh'
}

update_fixes_running_apps() {
  make_repo
  omv update >/dev/null
  assert_called '^doctor\.sh --fix$'
}

update_offers_undo_when_doctor_fails() {
  make_repo
  echo 1 > "$SANDBOX/doctor-exit"
  local output
  output=$(omv update 2>&1) && fail 'expected failure'
  [[ $output == *'omv update --undo'* ]] || fail "expected the undo hint in: $output"
}

update_suggests_fix_when_doctor_fails() {
  make_repo
  echo 1 > "$SANDBOX/doctor-exit"
  local output
  output=$(omv update 2>&1) && fail 'expected failure'
  [[ $output == *'omv doctor --fix'* ]] || fail "expected the fix hint in: $output"
}

update_offers_no_undo_without_saved_update() {
  make_repo
  touch "$SANDBOX/up-to-date"
  echo 1 > "$SANDBOX/doctor-exit"
  local output
  output=$(omv update 2>&1) && fail 'expected failure'
  [[ $output != *'omv update --undo'* ]] || fail "expected no undo hint in: $output"
}

update_installs_without_upgrading() {
  make_repo
  omv update >/dev/null
  assert_called '^brew bundle --no-upgrade '
}

points_hammerspoon_at_repo() {
  make_repo
  answer_hammerspoon_config "$HOME_DIR/.hammerspoon/init.lua"
  omv update >/dev/null
  assert_called "^defaults write org.hammerspoon.Hammerspoon MJConfigFile $REPO/config/hammerspoon/init.lua$"
}

leaves_hammerspoon_when_config_is_right() {
  make_repo
  run_hammerspoon
  omv update >/dev/null
  assert_not_called '^pkill'
}

restarts_hammerspoon_when_config_changed() {
  make_repo
  run_hammerspoon
  answer_hammerspoon_config "$HOME_DIR/.hammerspoon/init.lua"
  omv update >/dev/null
  assert_called '^open -a Hammerspoon$'
}

opens_no_stopped_hammerspoon() {
  make_repo
  stub pgrep 1
  answer_hammerspoon_config "$HOME_DIR/.hammerspoon/init.lua"
  omv update >/dev/null
  assert_not_called '^open -a Hammerspoon'
}

finishes_update_without_hammerspoon() {
  make_repo
  stub pgrep 1
  answer_hammerspoon_config "$HOME_DIR/.hammerspoon/init.lua"
  omv update >/dev/null 2>&1 || fail 'update failed'
  assert_called '^doctor\.sh'
}

relinks_opencode_plugin() {
  make_repo
  mkdir -p "$HOME_DIR/.config/opencode"
  omv update >/dev/null
  assert_called '^stow --dir=.*/agents .*--restow opencode$'
}

relinks_pi_extension() {
  make_repo
  mkdir -p "$HOME_DIR/.pi/agent"
  omv update >/dev/null
  assert_called '^stow --dir=.*/agents .*--restow pi$'
}

points_hammerspoon_when_stow_fails() {
  make_repo
  stub stow 1
  answer_hammerspoon_config "$HOME_DIR/.hammerspoon/init.lua"
  omv update >/dev/null 2>&1 || true
  assert_called '^defaults write org.hammerspoon.Hammerspoon MJConfigFile'
}

offers_no_undo_after_migration_stops() {
  make_repo
  add_migration 202601010000-a
  stub stow 1
  local output
  output=$(omv update 2>&1) && fail 'expected failure'
  [[ $output != *'omv update --undo'* ]] || fail "expected no undo hint in: $output"
}

says_run_update_again_after_migration_stops() {
  make_repo
  add_migration 202601010000-a
  stub stow 1
  local output
  output=$(omv update 2>&1) && fail 'expected failure'
  [[ $output == *'then run omv update again'* ]] || fail "expected the retry hint in: $output"
}

says_nothing_stopped_under_system_bash() {
  make_repo
  # Like the real one, defaults fails to read a key that isn't set.
  printf '#!/bin/sh\necho "defaults $*" >> "%s"\n[ "$1" = read ] && exit 1\nexit 0\n' "$CALL_LOG" > "$STUB_DIR/defaults"
  local output
  output=$(run_in_sandbox /bin/bash "$REPO/bin/omv" update 2>&1) || fail "update failed: $output"
  [[ $output != *'stopped partway'* ]] || fail "unexpected stop message in: $output"
}

readonly BUILT_HEADER="# Built by omv from its defaults and ~/.config/omv/aerospace.toml. Edit that file, then run omv reload."

built_aerospace() {
  cat "$HOME_DIR/.config/aerospace/aerospace.toml" 2>/dev/null
}

user_aerospace() {
  mkdir -p "$HOME_DIR/.config/omv"
  printf '%b' "$1" > "$HOME_DIR/.config/omv/aerospace.toml"
}

# pgrep finds AeroSpace, as it does Hammerspoon in run_hammerspoon.
run_aerospace() {
  printf '#!/bin/sh\necho "pgrep $*" >> "%s"\n[ "$*" = "-x AeroSpace" ] && echo 999998\nexit 0\n' "$CALL_LOG" > "$STUB_DIR/pgrep"
  chmod +x "$STUB_DIR/pgrep"
}

builds_aerospace_on_update() {
  make_repo
  omv update >/dev/null
  [ "$(built_aerospace | head -n 1)" = "$BUILT_HEADER" ] || fail "not built: $(built_aerospace | head -n 1)"
}

builds_aerospace_on_reload() {
  make_repo
  user_aerospace '[gaps]\ninner.horizontal = 3\n'
  omv reload >/dev/null
  [[ $(built_aerospace) == *'inner.horizontal = 3'* ]] || fail "user key missing in: $(built_aerospace)"
}

keeps_built_aerospace_on_user_error() {
  make_repo
  omv reload >/dev/null
  local before
  before=$(built_aerospace)
  user_aerospace '[gaps\n'
  assert_exit_nonzero omv reload
  [ "$(built_aerospace)" = "$before" ] || fail 'built file changed'
}

returns_to_defaults_without_user_file() {
  make_repo
  user_aerospace '[gaps]\ninner.horizontal = 3\n'
  omv reload >/dev/null
  rm "$HOME_DIR/.config/omv/aerospace.toml"
  omv reload >/dev/null
  [[ $(built_aerospace) == *'inner.horizontal = 10'* ]] || fail "defaults not back in: $(built_aerospace)"
}

reload_skips_stopped_aerospace() {
  make_repo
  stub pgrep 1
  omv reload >/dev/null || fail 'reload failed'
  assert_not_called '^aerospace reload-config'
}

reload_reloads_running_aerospace() {
  make_repo
  run_aerospace
  omv reload >/dev/null
  assert_called '^aerospace reload-config$'
}

refuses_to_build_through_clone_link() {
  make_repo
  mkdir -p "$HOME_DIR/.config"
  ln -s "$REPO/config/aerospace/.config/aerospace" "$HOME_DIR/.config/aerospace"
  omv reload >/dev/null 2>&1 || true
  [ ! -e "$REPO/config/aerospace/.config/aerospace/aerospace.toml.before-omv" ] || fail 'moved the repo defaults aside'
}

says_to_update_when_folder_is_linked() {
  make_repo
  mkdir -p "$HOME_DIR/.config"
  ln -s "$REPO/config/aerospace/.config/aerospace" "$HOME_DIR/.config/aerospace"
  local output
  output=$(omv reload 2>&1) && fail 'expected failure'
  [[ $output == *'omv update'* ]] || fail "expected the update hint in: $output"
}

reload_runs_pending_migrations() {
  make_repo
  add_migration 202601010000-a
  omv reload >/dev/null
  assert_called '^migration 202601010000-a$'
}

reload_fails_when_aerospace_rejects() {
  make_repo
  run_aerospace
  stub aerospace 1
  assert_exit_nonzero omv reload
}

finishes_update_with_bad_user_aerospace() {
  make_repo
  user_aerospace '[gaps\n'
  omv update >/dev/null 2>&1 || true
  assert_called '^doctor\.sh'
}

shows_last_valid_flag() {
  make_repo
  mkdir -p "$HOME_DIR/.config/omv"
  printf 'file-search=on\nfile-search=yes\n' > "$HOME_DIR/.config/omv/flags"
  [[ $(omv flags) == *'file-search  on'* ]] || fail "got: $(omv flags)"
}

runs_migrations_in_omv_folder() {
  make_repo
  printf '#!/bin/sh\necho "migration-pwd $(pwd -P)" >> "%s"\n' "$CALL_LOG" > "$REPO/migrations/202601010000-where.sh"
  (cd "$SANDBOX" && omv install --no-setup >/dev/null)
  assert_called "^migration-pwd $REPO$"
}

refuses_extra_update_argument() {
  make_repo
  local status=0
  omv update --undo now >/dev/null 2>&1 || status=$?
  [ "$status" = 2 ] || fail "expected exit 2, got $status"
}

refuses_extra_reload_argument() {
  make_repo
  local status=0
  omv reload now >/dev/null 2>&1 || status=$?
  [ "$status" = 2 ] || fail "expected exit 2, got $status"
}

update_reloads_running_aerospace() {
  make_repo
  run_aerospace
  omv update >/dev/null
  assert_called '^aerospace reload-config$'
}

update_skips_stopped_aerospace() {
  make_repo
  stub pgrep 1
  omv update >/dev/null 2>&1 || true
  assert_not_called '^aerospace reload-config'
}

# hs answers the load time: 100 for the first two asks, then 200, as a reload would.
reload_hammerspoon_slowly() {
  cat > "$STUB_DIR/hs" <<STUB
#!/bin/sh
echo "hs \$*" >> "$CALL_LOG"
case "\$*" in
  *omvLoadedAt*)
    count=\$((\$(cat "$SANDBOX/asks" 2>/dev/null || echo 0) + 1))
    echo "\$count" > "$SANDBOX/asks"
    [ "\$count" -le 2 ] && echo 100 || echo 200 ;;
esac
exit 0
STUB
  chmod +x "$STUB_DIR/hs"
}

waits_for_hammerspoon_before_doctor() {
  make_repo
  reload_hammerspoon_slowly
  omv update >/dev/null
  local asks
  asks=$(sed -n '/^doctor\.sh/q;p' "$CALL_LOG" | grep -c 'omvLoadedAt')
  [ "$asks" -ge 3 ] || fail "doctor ran after $asks asks:"$'\n'"$(cat "$CALL_LOG")"
}

names_unreadable_file_once() {
  make_repo
  user_aerospace '[gaps]\ninner.horizontal = 3\n'
  chmod 000 "$HOME_DIR/.config/omv/aerospace.toml"
  local output
  output=$(omv reload 2>&1 || true)
  [[ $output == *"~/.config/omv/aerospace.toml can't be read: Permission denied"* ]] || fail "got: $output"
}

says_aerospace_rejected_on_update() {
  make_repo
  run_aerospace
  stub aerospace 1
  local output
  output=$(omv update 2>&1 || true)
  [[ $output == *"AeroSpace didn't accept"* ]] || fail "got: $output"
}

fails_reload_on_unopenable_user_aerospace() {
  make_repo
  user_aerospace '[gaps]\ninner.horizontal = 3\n'
  chmod 000 "$HOME_DIR/.config/omv/aerospace.toml"
  assert_exit_nonzero omv reload
}

builds_readable_aerospace() {
  make_repo
  omv reload >/dev/null
  [ "$(stat -f %Lp "$HOME_DIR/.config/aerospace/aerospace.toml")" = 644 ] || fail "mode $(stat -f %Lp "$HOME_DIR/.config/aerospace/aerospace.toml")"
}

keeps_foreign_aerospace_when_aside_fails() {
  make_repo
  mkdir -p "$HOME_DIR/.config/aerospace"
  echo mine > "$HOME_DIR/.config/aerospace/aerospace.toml"
  chmod 555 "$HOME_DIR/.config/aerospace"
  omv reload >/dev/null 2>&1 || true
  chmod 755 "$HOME_DIR/.config/aerospace"
  [ "$(cat "$HOME_DIR/.config/aerospace/aerospace.toml")" = mine ] || fail 'foreign file overwritten'
}

keeps_earlier_backup() {
  make_repo
  mkdir -p "$HOME_DIR/.config/aerospace"
  echo older > "$HOME_DIR/.config/aerospace/aerospace.toml.before-omv"
  echo mine > "$HOME_DIR/.config/aerospace/aerospace.toml"
  omv reload >/dev/null
  [ "$(cat "$HOME_DIR/.config/aerospace/aerospace.toml.before-omv")" = older ] || fail 'earlier backup changed'
}

backs_up_beside_earlier_backup() {
  make_repo
  mkdir -p "$HOME_DIR/.config/aerospace"
  echo older > "$HOME_DIR/.config/aerospace/aerospace.toml.before-omv"
  echo mine > "$HOME_DIR/.config/aerospace/aerospace.toml"
  omv reload >/dev/null
  grep -qx mine "$HOME_DIR"/.config/aerospace/aerospace.toml.before-omv.* 2>/dev/null || fail 'second backup missing'
}

builds_beside_earlier_backup() {
  make_repo
  mkdir -p "$HOME_DIR/.config/aerospace"
  echo older > "$HOME_DIR/.config/aerospace/aerospace.toml.before-omv"
  echo mine > "$HOME_DIR/.config/aerospace/aerospace.toml"
  omv reload >/dev/null
  [ "$(built_aerospace | head -n 1)" = "$BUILT_HEADER" ] || fail 'not built'
}

blames_no_user_file_when_build_step_fails() {
  make_repo
  mkdir -p "$HOME_DIR/.config/aerospace"
  echo mine > "$HOME_DIR/.config/aerospace/aerospace.toml"
  chmod 555 "$HOME_DIR/.config/aerospace"
  local output
  output=$(omv update 2>&1 || true)
  chmod 755 "$HOME_DIR/.config/aerospace"
  [[ $output != *'fix ~/.config/omv/aerospace.toml'* ]] || fail "blamed the user file in: $output"
}

readonly SETUP_APP_PATTERN='^open .*/Applications/omv Setup\.app( |$)'

# swiftc "builds" by writing the file after -o, as the real one would.
build_with_stub_swiftc() {
  cat > "$STUB_DIR/swiftc" <<STUB
#!/bin/sh
echo "swiftc \$*" >> "$CALL_LOG"
while [ "\$#" -gt 0 ]; do [ "\$1" = -o ] && { printf '#!/bin/sh\\n' > "\$2"; chmod +x "\$2"; }; shift; done
exit 0
STUB
  chmod +x "$STUB_DIR/swiftc"
}

setup_opens_app() {
  make_repo
  build_with_stub_swiftc
  omv setup >/dev/null
  assert_called "$SETUP_APP_PATTERN"
}

setup_passes_repo() {
  make_repo
  build_with_stub_swiftc
  omv setup >/dev/null
  assert_called "^open .*/Applications/omv Setup\.app --args --repo $REPO$"
}

setup_builds_before_opening() {
  make_repo
  build_with_stub_swiftc
  omv setup >/dev/null
  assert_before '^swiftc ' "$SETUP_APP_PATTERN"
}

setup_says_how_to_fix_build() {
  make_repo
  stub swiftc 1
  local output
  output=$(omv setup 2>&1) && fail 'expected failure'
  [[ $output == *'xcode-select --install'* ]] || fail "no fix in: $output"
}

install_builds_setup_first() {
  make_repo
  build_with_stub_swiftc
  omv install >/dev/null
  assert_before '^swiftc ' '^open '
}

install_opens_setup_in_install_mode() {
  make_repo
  build_with_stub_swiftc
  omv install >/dev/null
  assert_called "^open .*/Applications/omv Setup\.app --args --install $REPO$"
}

install_passes_no_apps_to_setup() {
  make_repo
  build_with_stub_swiftc
  omv install --no-apps >/dev/null
  assert_called "^open .*/Applications/omv Setup\.app --args --install $REPO --no-apps$"
}

# pgrep finds omv Setup's binary, as it would while the app is open.
setup_app_running() {
  printf '#!/bin/sh\necho "pgrep $*" >> "%s"\ncase "$*" in *omv-setup*) echo 4242 ;; *) exit 1 ;; esac\n' "$CALL_LOG" > "$STUB_DIR/pgrep"
  chmod +x "$STUB_DIR/pgrep"
}

install_says_setup_is_open() {
  make_repo
  build_with_stub_swiftc
  setup_app_running
  local output
  output=$(omv install 2>&1) && fail 'expected failure'
  [[ $output == *'omv Setup is already open; quit it first'* ]] || fail "no message in: $output"
}

install_opens_no_second_setup() {
  make_repo
  build_with_stub_swiftc
  setup_app_running
  omv install >/dev/null 2>&1 || true
  assert_not_called '^open '
}

setup_says_setup_is_open() {
  make_repo
  build_with_stub_swiftc
  setup_app_running
  local output
  output=$(omv setup 2>&1) && fail 'expected failure'
  [[ $output == *'omv Setup is already open; quit it first'* ]] || fail "no message in: $output"
}

install_points_to_setup() {
  make_repo
  build_with_stub_swiftc
  [[ $(omv install) == *'Continue in omv Setup'* ]] || fail 'no pointer to omv Setup'
}

install_leaves_install_to_setup() {
  make_repo
  build_with_stub_swiftc
  omv install >/dev/null
  assert_not_called '^install\.sh'
}

installs_in_terminal_with_no_setup() {
  make_repo
  build_with_stub_swiftc
  omv install --no-setup >/dev/null
  assert_called '^install\.sh ?$'
}

opens_no_setup_with_no_setup() {
  make_repo
  build_with_stub_swiftc
  omv install --no-setup >/dev/null
  assert_not_called '^open '
}

installs_in_terminal_when_setup_cant_build() {
  make_repo
  stub swiftc 1
  omv install >/dev/null 2>&1 || true
  assert_called '^install\.sh ?$'
}

rejects_unknown_install_flag() {
  make_repo
  local status=0
  omv install --bogus >/dev/null 2>&1 || status=$?
  [ "$status" = 2 ] || fail "expected exit 2, got $status"
}

dry_run_install_opens_no_setup() {
  make_repo
  build_with_stub_swiftc
  omv install --dry-run >/dev/null
  assert_not_called '^swiftc '
}

undo_resets_to_saved_commit() {
  make_repo
  omv update >/dev/null
  omv update --undo >/dev/null
  assert_called '^git -C .* reset --hard aaa111$'
}

undo_refuses_without_saved_commit() {
  make_repo
  assert_exit_nonzero omv update --undo
  assert_not_called 'reset --hard'
}

undo_refuses_dirty_tree() {
  make_repo
  omv update >/dev/null
  echo ' M README.md' > "$SANDBOX/dirty"
  assert_exit_nonzero omv update --undo
  assert_not_called 'reset --hard'
}

runs_migrations_in_order() {
  make_repo
  add_migration 202611160900-second
  add_migration 202611150900-first
  omv update >/dev/null
  [ "$(grep '^migration' "$CALL_LOG" | tr '\n' ' ')" = 'migration 202611150900-first migration 202611160900-second ' ] \
    || fail "ran: $(grep '^migration' "$CALL_LOG")"
}

skips_done_migrations() {
  make_repo
  add_migration 202611150900-first
  omv update >/dev/null
  : > "$CALL_LOG"
  omv update >/dev/null
  assert_not_called '^migration'
}

stops_on_failed_migration() {
  make_repo
  add_migration 202611150900-it-fails
  add_migration 202611160900-later
  local output
  output=$(omv update 2>&1) && fail 'expected failure'
  [[ $output == *'202611150900-it-fails'* ]] || fail "expected the migration's name in: $output"
  assert_not_called '^migration 202611160900-later'
}

does_not_record_failed_migration() {
  make_repo
  add_migration 202611150900-it-fails
  omv update >/dev/null 2>&1 || true
  ! grep -q it-fails "$HOME_DIR/.local/state/omv/migrations" 2>/dev/null || fail 'recorded a failed migration'
}

lists_flag_defaults() {
  make_repo
  [[ $(omv flags) == *'file-search  off'* ]] || fail "got: $(omv flags)"
}

sets_flag_on() {
  make_repo
  omv flags file-search on >/dev/null
  grep -qx 'file-search=on' "$HOME_DIR/.config/omv/flags" || fail "flags: $(cat "$HOME_DIR/.config/omv/flags" 2>&1)"
}

replaces_existing_flag() {
  make_repo
  mkdir -p "$HOME_DIR/.config/omv"
  printf '# mine\nfile-search=on\n' > "$HOME_DIR/.config/omv/flags"
  omv flags file-search off >/dev/null
  [ "$(cat "$HOME_DIR/.config/omv/flags")" = $'# mine\nfile-search=off' ] || fail "flags: $(cat "$HOME_DIR/.config/omv/flags")"
}

rejects_unknown_flag() {
  make_repo
  assert_exit_nonzero omv flags nope on
}

rejects_bad_flag_value() {
  make_repo
  assert_exit_nonzero omv flags file-search yes
}

reloads_after_flag_change() {
  make_repo
  omv flags file-search on >/dev/null
  assert_called '^hs .*hs\.reload'
}

lists_every_flag() {
  make_repo
  local expected
  expected=$(grep -cE '^[[:space:]]*\["[a-z-]+"\][[:space:]]*=' "$REPO_DIR/config/hammerspoon/flags.lua")
  [ "$(omv flags | wc -l | tr -d ' ')" = "$expected" ] || fail "listed: $(omv flags | wc -l)"
}

readonly GHOSTTY_FLAGS=state/omv/ghostty-flags

turns_drop_down_terminal_off_in_ghostty() {
  make_repo
  omv flags drop-down-terminal off >/dev/null
  grep -qx 'keybind = global:alt+backquote=unbind' "$HOME_DIR/.local/$GHOSTTY_FLAGS" \
    || fail "ghostty flags: $(cat "$HOME_DIR/.local/$GHOSTTY_FLAGS" 2>&1)"
}

turns_long_command_notices_off_in_ghostty() {
  make_repo
  omv flags long-command-notices off >/dev/null
  grep -qx 'notify-on-command-finish = never' "$HOME_DIR/.local/$GHOSTTY_FLAGS" \
    || fail "ghostty flags: $(cat "$HOME_DIR/.local/$GHOSTTY_FLAGS" 2>&1)"
}

leaves_ghostty_alone_with_its_flags_on() {
  make_repo
  omv flags drop-down-terminal off >/dev/null
  omv flags drop-down-terminal on >/dev/null
  ! grep -qE 'keybind|notify' "$HOME_DIR/.local/$GHOSTTY_FLAGS" || fail "ghostty flags: $(cat "$HOME_DIR/.local/$GHOSTTY_FLAGS")"
}

writes_ghostty_flags_on_reload() {
  make_repo
  mkdir -p "$HOME_DIR/.config/omv"
  echo 'long-command-notices=off' > "$HOME_DIR/.config/omv/flags"
  omv reload >/dev/null
  grep -qx 'notify-on-command-finish = never' "$HOME_DIR/.local/$GHOSTTY_FLAGS" \
    || fail "ghostty flags: $(cat "$HOME_DIR/.local/$GHOSTTY_FLAGS" 2>&1)"
}

applies_theme() {
  make_repo
  mkdir -p "$HOME_DIR/.local/share/omv/themes/nord"
  touch "$HOME_DIR/.local/share/omv/themes/nord/colors.toml"
  omv theme nord >/dev/null
  assert_called "^hs .*omvSetTheme\\(\"nord\"\\)"
}

rejects_unknown_theme() {
  make_repo
  assert_exit_nonzero omv theme nope
  assert_not_called 'omvSetTheme'
}

lists_themes() {
  make_repo
  mkdir -p "$HOME_DIR/.local/share/omv/themes/nord"
  touch "$HOME_DIR/.local/share/omv/themes/nord/colors.toml"
  [ "$(omv theme)" = $'nord\nvantablack' ] || fail "got: $(omv theme)"
}

lists_vantablack_once() {
  make_repo
  mkdir -p "$HOME_DIR/.local/share/omv/themes/vantablack"
  touch "$HOME_DIR/.local/share/omv/themes/vantablack/colors.toml"
  [ "$(omv theme)" = vantablack ] || fail "got: $(omv theme)"
}

passes_doctor_arguments() {
  make_repo
  omv doctor --fix >/dev/null
  assert_called '^doctor\.sh --fix$'
}

passes_uninstall_arguments() {
  make_repo
  omv uninstall --all >/dev/null
  assert_called '^uninstall\.sh --all$'
}

install_runs_migrations() {
  make_repo
  add_migration 202611150900-first
  omv install --no-apps --no-setup >/dev/null
  assert_called '^install\.sh --no-apps$'
  assert_called '^migration 202611150900-first$'
}

lists_themes_without_folder() {
  make_repo
  local output status=0
  output=$(omv theme) || status=$?
  [ "$status" = 0 ] || fail "exit $status"
  [ "$output" = vantablack ] || fail "got: $output"
}

applies_vantablack_without_folder() {
  make_repo
  omv theme vantablack >/dev/null || fail 'vantablack refused'
  assert_called 'omvSetTheme\("vantablack"\)'
}

rejects_theme_name_with_lua() {
  make_repo
  assert_exit_nonzero omv theme 'vantablack")os.execute("x")--\|.*'
  assert_not_called 'omvSetTheme'
}

relinks_with_pulled_packages() {
  make_repo
  printf '#!/bin/sh\nprintf "readonly CONFIG_PACKAGES=(hammerspoon extra)\\nreadonly AGENT_PACKAGES=(claude)\\n" > "%s/install/packages.sh"\n' "$REPO" > "$SANDBOX/on-pull"
  chmod +x "$SANDBOX/on-pull"
  omv update >/dev/null
  assert_called '^stow .*--restow hammerspoon extra$'
}

offers_undo_when_install_fails_after_pull() {
  make_repo
  stub brew 1
  local output
  output=$(omv update 2>&1) && fail 'expected failure'
  [[ $output == *'omv update --undo'* ]] || fail "expected the undo hint in: $output"
}

keeps_saved_commit_when_nothing_was_pulled() {
  make_repo
  omv update >/dev/null
  touch "$SANDBOX/up-to-date"
  omv update >/dev/null
  [ "$(saved_commit)" = aaa111 ] || fail "saved: $(saved_commit)"
}

keeps_saved_commit_when_pull_fails() {
  make_repo
  omv update >/dev/null
  touch "$SANDBOX/pull-fails"
  omv update >/dev/null 2>&1 || true
  [ "$(saved_commit)" = aaa111 ] || fail "saved: $(saved_commit)"
}

undo_refuses_after_new_commits() {
  make_repo
  omv update >/dev/null
  echo ccc333 > "$SANDBOX/head"
  assert_exit_nonzero omv update --undo
  assert_not_called 'reset --hard'
}

undo_refuses_after_migrations() {
  make_repo
  add_migration 202611150900-first
  omv update >/dev/null
  assert_exit_nonzero omv update --undo
  assert_not_called 'reset --hard'
}

dry_run_install_runs_no_migrations() {
  make_repo
  add_migration 202611150900-first
  omv install --dry-run >/dev/null
  assert_not_called '^migration'
}

rejects_flag_name_pattern() {
  make_repo
  assert_exit_nonzero omv flags file.search on
}

shows_version() {
  make_repo
  [ "$(omv version)" = 'omv aaa111 2026-11-15' ] || fail "got: $(omv version)"
}

run_case 'should show usage when no command is given' shows_usage_without_command
run_case 'should show usage for an unknown command' shows_usage_for_unknown_command
run_case 'should refuse to update a tree with changes' update_refuses_dirty_tree
run_case 'should refuse to update a branch other than main' update_refuses_other_branch
run_case 'should save the commit before updating' update_saves_commit
run_case 'should pull fast-forward only' update_pulls_fast_forward_only
run_case 'should relink the configs after pulling' update_restows
run_case 'should reload Hammerspoon after updating' update_reloads_hammerspoon
run_case 'should reload the bar after updating' update_reloads_bar
run_case 'should run the doctor after updating' update_runs_doctor
run_case 'should let the doctor fix running apps after updating' update_fixes_running_apps
run_case 'should offer undo when the doctor fails after an update' update_offers_undo_when_doctor_fails
run_case 'should suggest omv doctor --fix when the doctor fails after an update' update_suggests_fix_when_doctor_fails
run_case 'should offer no undo when the doctor fails and no update is saved' update_offers_no_undo_without_saved_update
run_case 'should install missing packages without upgrading others when updating' update_installs_without_upgrading
run_case "should point Hammerspoon at the repo's config when relinking" points_hammerspoon_at_repo
run_case "should leave Hammerspoon running when it already loads the repo's config" leaves_hammerspoon_when_config_is_right
run_case 'should restart Hammerspoon when its config changed' restarts_hammerspoon_when_config_changed
run_case "should not open Hammerspoon when it isn't running" opens_no_stopped_hammerspoon
run_case "should finish the update when Hammerspoon isn't running" finishes_update_without_hammerspoon
run_case 'should relink the OpenCode plugin when OpenCode is set up' relinks_opencode_plugin
run_case 'should relink the pi extension when pi is set up' relinks_pi_extension
run_case 'should point Hammerspoon at the repo even when linking fails' points_hammerspoon_when_stow_fails
run_case 'should offer no undo when an update that ran a migration stops partway' offers_no_undo_after_migration_stops
run_case 'should say to run the update again when one that ran a migration stops partway' says_run_update_again_after_migration_stops
run_case 'should say nothing stopped when an update succeeds under the system bash' says_nothing_stopped_under_system_bash
run_case 'should build aerospace.toml when updating' builds_aerospace_on_update
run_case "should build aerospace.toml with the user's settings on reload" builds_aerospace_on_reload
run_case "should keep the built aerospace.toml when the user's has an error" keeps_built_aerospace_on_user_error
run_case "should go back to omv's defaults when the user file is removed" returns_to_defaults_without_user_file
run_case "should rebuild without reloading AeroSpace when it isn't running" reload_skips_stopped_aerospace
run_case "should reload AeroSpace when it's running" reload_reloads_running_aerospace
run_case "should not build through a folder link into the clone" refuses_to_build_through_clone_link
run_case 'should say to run omv update when ~/.config/aerospace is still a link' says_to_update_when_folder_is_linked
run_case 'should run pending migrations on reload' reload_runs_pending_migrations
run_case 'should fail the reload when AeroSpace rejects the built file' reload_fails_when_aerospace_rejects
run_case "should finish the update when the user's aerospace.toml has an error" finishes_update_with_bad_user_aerospace
run_case 'should show the last valid value when a later flag line is invalid' shows_last_valid_flag
run_case 'should run a migration in the omv folder when omv starts from another folder' runs_migrations_in_omv_folder
run_case 'should show usage when update gets an extra argument' refuses_extra_update_argument
run_case 'should show usage when reload gets an extra argument' refuses_extra_reload_argument
run_case "should reload AeroSpace after updating when it's running" update_reloads_running_aerospace
run_case "should not reload AeroSpace after updating when it isn't running" update_skips_stopped_aerospace
run_case 'should wait for Hammerspoon to answer before the doctor runs after updating' waits_for_hammerspoon_before_doctor
run_case "should fail the reload when the user's aerospace.toml can't be opened" fails_reload_on_unopenable_user_aerospace
run_case 'should build an aerospace.toml everyone can read' builds_readable_aerospace
run_case "should keep a foreign aerospace.toml when it can't be moved aside" keeps_foreign_aerospace_when_aside_fails
run_case 'should keep an earlier backup when another aerospace.toml is moved aside' keeps_earlier_backup
run_case 'should back up beside an earlier backup when one exists' backs_up_beside_earlier_backup
run_case 'should build aerospace.toml when an earlier backup exists' builds_beside_earlier_backup
run_case "should not blame the user's file when a build step fails" blames_no_user_file_when_build_step_fails
run_case "should name an unreadable aerospace.toml once when it can't be read" names_unreadable_file_once
run_case "should say AeroSpace didn't accept the config when its reload fails during an update" says_aerospace_rejected_on_update
run_case 'should open the setup app when running omv setup' setup_opens_app
run_case "should give the setup app the repo's path on omv setup" setup_passes_repo
run_case 'should build the setup app before opening it' setup_builds_before_opening
run_case "should say how to fix it when the setup app can't be built" setup_says_how_to_fix_build
run_case 'should build the setup app first when installing' install_builds_setup_first
run_case "should open the setup app in install mode with the repo's path" install_opens_setup_in_install_mode
run_case 'should leave the install to the setup app when it opens' install_leaves_install_to_setup
run_case 'should pass --no-apps to the setup app when installing without apps' install_passes_no_apps_to_setup
run_case 'should say omv Setup is open when installing while it runs' install_says_setup_is_open
run_case 'should open no second omv Setup when installing while it runs' install_opens_no_second_setup
run_case 'should say omv Setup is open when running omv setup while it runs' setup_says_setup_is_open
run_case 'should point to omv Setup when it opens for the install' install_points_to_setup
run_case 'should install in the terminal with --no-setup' installs_in_terminal_with_no_setup
run_case 'should open no setup app with --no-setup' opens_no_setup_with_no_setup
run_case "should install in the terminal when the setup app can't be built" installs_in_terminal_when_setup_cant_build
run_case 'should show usage for an unknown install flag' rejects_unknown_install_flag
run_case 'should not build the setup app on a dry-run install' dry_run_install_opens_no_setup
run_case 'should go back to the saved commit on undo' undo_resets_to_saved_commit
run_case 'should refuse undo without a saved commit' undo_refuses_without_saved_commit
run_case 'should refuse undo on a tree with changes' undo_refuses_dirty_tree
run_case 'should run migrations before relinking when updating' migrates_before_relinking
run_case 'should relink before installing missing packages when updating' relinks_before_installing_packages
run_case 'should run migrations before installing' migrates_before_installing
run_case 'should run pending migrations in name order' runs_migrations_in_order
run_case 'should skip migrations that already ran' skips_done_migrations
run_case 'should stop at a failed migration and name it' stops_on_failed_migration
run_case 'should not record a failed migration as done' does_not_record_failed_migration
run_case 'should list each flag with its default' lists_flag_defaults
run_case 'should turn a flag on' sets_flag_on
run_case "should replace a flag's line and keep the others" replaces_existing_flag
run_case 'should reject an unknown flag' rejects_unknown_flag
run_case "should reject a flag value that isn't on or off" rejects_bad_flag_value
run_case 'should reload Hammerspoon after a flag changes' reloads_after_flag_change
run_case 'should list every flag' lists_every_flag
run_case "should take the drop-down terminal's key out of Ghostty when its flag is off" turns_drop_down_terminal_off_in_ghostty
run_case "should turn Ghostty's long-command notices off when their flag is off" turns_long_command_notices_off_in_ghostty
run_case 'should leave Ghostty unchanged when its flags are on' leaves_ghostty_alone_with_its_flags_on
run_case "should write Ghostty's flags when omv reloads" writes_ghostty_flags_on_reload
run_case 'should apply a theme through Hammerspoon' applies_theme
run_case 'should reject an unknown theme' rejects_unknown_theme
run_case 'should list the themes, Vantablack included' lists_themes
run_case 'should list Vantablack once when it also has a folder' lists_vantablack_once
run_case "should pass the doctor's arguments through" passes_doctor_arguments
run_case "should pass uninstall's arguments through" passes_uninstall_arguments
run_case 'should run migrations after installing' install_runs_migrations
run_case 'should list Vantablack when there is no themes folder' lists_themes_without_folder
run_case 'should apply Vantablack when there is no themes folder' applies_vantablack_without_folder
run_case 'should refuse a theme name that holds Lua' rejects_theme_name_with_lua
run_case "should relink with the pulled packages list" relinks_with_pulled_packages
run_case 'should offer undo when installing fails after the pull' offers_undo_when_install_fails_after_pull
run_case 'should keep the saved commit when nothing was pulled' keeps_saved_commit_when_nothing_was_pulled
run_case 'should keep the saved commit when the pull fails' keeps_saved_commit_when_pull_fails
run_case 'should refuse undo after commits made since the update' undo_refuses_after_new_commits
run_case 'should refuse undo after an update that ran migrations' undo_refuses_after_migrations
run_case 'should run no migrations on a dry-run install' dry_run_install_runs_no_migrations
run_case 'should refuse a flag name that is a pattern' rejects_flag_name_pattern
run_case 'should show the commit and its date' shows_version
finish
