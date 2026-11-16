#!/usr/bin/env bash
# Behavior of the migration to the new layout: it removes the links into the clone's old
# package folders, and only those. It runs from a copy in a fake clone whose path holds a
# space, against a temporary HOME.

source "$(dirname "$0")/lib.sh"

readonly MIGRATION=202611161200-new-layout.sh

# A clone named "my omv" holding the migration, as after the pull: the old folders are gone.
make_clone() {
  CLONE="$SANDBOX/my omv"
  mkdir -p "$CLONE/migrations" "$CLONE/config/aerospace/.config/aerospace"
  cp "$REPO_DIR/migrations/$MIGRATION" "$CLONE/migrations/"
}

migrate() {
  run_in_sandbox bash "$CLONE/migrations/$MIGRATION"
}

# Links $1 (under the home) to the text $2, making its folder first.
link() {
  mkdir -p "$(dirname "$HOME_DIR/$1")"
  ln -s "$2" "$HOME_DIR/$1"
}

assert_gone() {
  [ ! -L "$HOME_DIR/$1" ] || fail "link kept: $1"
}

assert_kept() {
  [ -L "$HOME_DIR/$1" ] || [ -f "$HOME_DIR/$1" ] || fail "removed: $1"
}

removes_file_link() {
  make_clone
  link .hammerspoon/init.lua '../../my omv/hammerspoon/.hammerspoon/init.lua'
  migrate >/dev/null
  assert_gone .hammerspoon/init.lua
}

removes_folder_link() {
  make_clone
  link .config/aerospace '../../my omv/aerospace/.config/aerospace'
  migrate >/dev/null
  assert_gone .config/aerospace
}

removes_absolute_link() {
  make_clone
  link .claude/bar-usage.sh "$CLONE/claude/.claude/bar-usage.sh"
  migrate >/dev/null
  assert_gone .claude/bar-usage.sh
}

keeps_new_layout_link() {
  make_clone
  link .config/aerospace '../../my omv/config/aerospace/.config/aerospace'
  migrate >/dev/null
  assert_kept .config/aerospace
}

keeps_outside_link() {
  make_clone
  link .config/foo /opt/x
  migrate >/dev/null
  assert_kept .config/foo
}

keeps_real_file() {
  make_clone
  mkdir -p "$HOME_DIR/.hammerspoon/Spoons"
  echo 'mine' > "$HOME_DIR/.hammerspoon/Spoons/a.lua"
  migrate >/dev/null
  assert_kept .hammerspoon/Spoons/a.lua
}

keeps_similar_clone_link() {
  make_clone
  link .config/aerospace '../../my omv2/aerospace/.config/aerospace'
  migrate >/dev/null
  assert_kept .config/aerospace
}

does_nothing_on_fresh_home() {
  make_clone
  local output
  output=$(migrate) || fail 'expected exit 0'
  [ -z "$output" ] || fail "expected no output, got: $output"
}

succeeds_twice() {
  make_clone
  link .config/aerospace '../../my omv/aerospace/.config/aerospace'
  migrate >/dev/null
  migrate >/dev/null || fail 'second run failed'
}

matches_through_symlinked_home() {
  make_clone
  link .config/nvim '../../my omv/nvim/.config/nvim'
  ln -s "$HOME_DIR" "$SANDBOX/home-link"
  env -i HOME="$SANDBOX/home-link" PATH="$STUB_DIR:/usr/bin:/bin" bash "$CLONE/migrations/$MIGRATION" >/dev/null
  assert_gone .config/nvim
}

matches_clone_path_with_brackets() {
  CLONE="$SANDBOX/omv[1]"
  mkdir -p "$CLONE/migrations"
  cp "$REPO_DIR/migrations/$MIGRATION" "$CLONE/migrations/"
  link .config/nvim '../../omv[1]/nvim/.config/nvim'
  touch "$SANDBOX/omv1"
  (cd "$SANDBOX" && run_in_sandbox bash "$CLONE/migrations/$MIGRATION" >/dev/null)
  assert_gone .config/nvim
}

run_case "should match a link whose path holds brackets when a file matches them as a pattern" matches_clone_path_with_brackets
run_case 'should remove a file link into an old package' removes_file_link
run_case 'should remove a folder link into an old package' removes_folder_link
run_case 'should remove a link with an absolute target into an old package' removes_absolute_link
run_case 'should keep a link into the new layout' keeps_new_layout_link
run_case 'should keep a link that points outside the clone' keeps_outside_link
run_case 'should keep a real file' keeps_real_file
run_case 'should keep a link into a different clone with a similar name' keeps_similar_clone_link
run_case 'should do nothing when the home has no omv links' does_nothing_on_fresh_home
run_case 'should succeed when run twice' succeeds_twice
run_case 'should match links when the home is reached through a symlink' matches_through_symlinked_home
finish
