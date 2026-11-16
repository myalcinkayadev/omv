#!/usr/bin/env bash
# Behavior of the migration to a built aerospace.toml: it removes omv's ~/.config/aerospace
# link, so omv can write the built file there, and leaves anything else.

source "$(dirname "$0")/lib.sh"

readonly MIGRATION=202611161400-built-aerospace.sh

# A clone named "my omv" with the migration and omv's AeroSpace folder.
make_clone() {
  CLONE="$SANDBOX/my omv"
  mkdir -p "$CLONE/migrations" "$CLONE/config/aerospace/.config/aerospace"
  touch "$CLONE/config/aerospace/.config/aerospace/aerospace.toml"
  cp "$REPO_DIR/migrations/$MIGRATION" "$CLONE/migrations/"
  mkdir -p "$HOME_DIR/.config"
}

migrate() {
  run_in_sandbox bash "$CLONE/migrations/$MIGRATION"
}

removes_omv_link() {
  make_clone
  ln -s '../../my omv/config/aerospace/.config/aerospace' "$HOME_DIR/.config/aerospace"
  migrate >/dev/null
  [ ! -L "$HOME_DIR/.config/aerospace" ] || fail 'link kept'
}

keeps_real_folder() {
  make_clone
  mkdir -p "$HOME_DIR/.config/aerospace"
  echo mine > "$HOME_DIR/.config/aerospace/aerospace.toml"
  migrate >/dev/null
  [ "$(cat "$HOME_DIR/.config/aerospace/aerospace.toml")" = mine ] || fail 'real folder changed'
}

keeps_other_link() {
  make_clone
  mkdir -p "$SANDBOX/elsewhere"
  ln -s "$SANDBOX/elsewhere" "$HOME_DIR/.config/aerospace"
  migrate >/dev/null
  [ -L "$HOME_DIR/.config/aerospace" ] || fail 'link elsewhere removed'
}

succeeds_twice() {
  make_clone
  ln -s '../../my omv/config/aerospace/.config/aerospace' "$HOME_DIR/.config/aerospace"
  migrate >/dev/null
  migrate >/dev/null || fail 'second run failed'
}

run_case "should remove omv's ~/.config/aerospace link" removes_omv_link
run_case 'should keep a real ~/.config/aerospace folder' keeps_real_folder
run_case 'should keep a ~/.config/aerospace link that points elsewhere' keeps_other_link
run_case 'should succeed when run twice' succeeds_twice
finish
