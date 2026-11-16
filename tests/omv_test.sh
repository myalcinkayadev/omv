#!/usr/bin/env bash
# Behavior of bin/omv, the one command over install, update, doctor, flags and themes.
# It runs from a copy in a sandbox repo with stub scripts, so update never touches this repo.

source "$(dirname "$0")/lib.sh"

# A repo with the real omv, packages list and flag defaults, and stub install, uninstall and
# doctor scripts (in install/) that log their arguments. git answers from files: $SANDBOX/dirty (status),
# $SANDBOX/branch (main by default) and $SANDBOX/head (the commit).
make_repo() {
  REPO=$SANDBOX/repo
  mkdir -p "$REPO/bin" "$REPO/install" "$REPO/migrations" "$REPO/config/hammerspoon/.hammerspoon"
  cp "$REPO_DIR/bin/omv" "$REPO/bin/omv"
  cp "$REPO_DIR/install/packages.sh" "$REPO/install/packages.sh"
  cp "$REPO_DIR/config/hammerspoon/.hammerspoon/flags.lua" "$REPO/config/hammerspoon/.hammerspoon/flags.lua"
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
  assert_called '^stow .*--restow .*hammerspoon'
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
  omv install --no-apps >/dev/null
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
run_case 'should offer undo when the doctor fails after an update' update_offers_undo_when_doctor_fails
run_case 'should suggest omv doctor --fix when the doctor fails after an update' update_suggests_fix_when_doctor_fails
run_case 'should offer no undo when the doctor fails and no update is saved' update_offers_no_undo_without_saved_update
run_case 'should install missing packages without upgrading others when updating' update_installs_without_upgrading
run_case 'should go back to the saved commit on undo' undo_resets_to_saved_commit
run_case 'should refuse undo without a saved commit' undo_refuses_without_saved_commit
run_case 'should refuse undo on a tree with changes' undo_refuses_dirty_tree
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
