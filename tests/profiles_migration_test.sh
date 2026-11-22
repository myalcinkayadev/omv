#!/usr/bin/env bash
# Behavior of the migration that renames ~/.config/omv/displays to ~/.config/omv/profiles,
# since a profile now holds workspaces and apps, not only displays.

source "$(dirname "$0")/lib.sh"

readonly MIGRATION=202611221600-profiles-file.sh

migrate() {
  run_in_sandbox bash "$REPO_DIR/migrations/$MIGRATION"
}

renames_the_displays_file() {
  mkdir -p "$HOME_DIR/.config/omv"
  printf '[desk]\nwhen = laptop\n' > "$HOME_DIR/.config/omv/displays"
  migrate >/dev/null || fail 'the migration failed'
  [ ! -e "$HOME_DIR/.config/omv/displays" ] || fail 'displays kept'
  grep -q '^\[desk\]' "$HOME_DIR/.config/omv/profiles" || fail 'profiles missing its content'
}

keeps_both_when_profiles_exists() {
  mkdir -p "$HOME_DIR/.config/omv"
  echo old > "$HOME_DIR/.config/omv/displays"
  echo new > "$HOME_DIR/.config/omv/profiles"
  migrate >/dev/null || fail 'the migration failed'
  [ "$(cat "$HOME_DIR/.config/omv/profiles")" = new ] || fail 'profiles overwritten'
  [ "$(cat "$HOME_DIR/.config/omv/displays")" = old ] || fail 'displays removed'
}

does_nothing_without_a_displays_file() {
  migrate >/dev/null || fail 'the migration failed'
  [ ! -e "$HOME_DIR/.config/omv/profiles" ] || fail 'profiles made from nothing'
}

run_case 'should rename the displays file to profiles' renames_the_displays_file
run_case 'should leave both files when profiles already exists' keeps_both_when_profiles_exists
run_case 'should do nothing without a displays file' does_nothing_without_a_displays_file
finish
