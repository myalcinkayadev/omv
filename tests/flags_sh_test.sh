#!/usr/bin/env bash
# Behavior of flags.sh, which the bar's config and bin/omv source to read feature flags as
# Hammerspoon's flags.lua does: its defaults, then ~/.config/omv/flags.

source "$(dirname "$0")/lib.sh"

readonly HELPER=$REPO_DIR/config/sketchybar/.config/sketchybar/flags.sh
readonly DEFAULTS=$REPO_DIR/config/hammerspoon/flags.lua

flags_file() {
  mkdir -p "$HOME_DIR/.config/omv"
  printf '%b' "$1" > "$HOME_DIR/.config/omv/flags"
}

# Exits 0 when the flag is on.
flag_on() {
  run_in_sandbox bash -c 'OMV_FLAG_DEFAULTS=$1; source "$2"; omv_flag_on "$3"' _ "$DEFAULTS" "$HELPER" "$1"
}

on_by_default() { flag_on weather; }
off_by_default() { ! flag_on file-search; }
turned_off() { flags_file 'weather=off\n'; ! flag_on weather; }
turned_on() { flags_file 'file-search=on\n'; flag_on file-search; }
others_untouched() { flags_file 'weather=off\n'; flag_on battery; }
last_line_wins() { flags_file 'weather=off\nweather=on\n'; flag_on weather; }
ignores_bad_value() { flags_file 'weather=nope\n'; flag_on weather; }
ignores_comment() { flags_file '# weather=off\n'; flag_on weather; }
unknown_flag_off() { flags_file 'nope=on\n'; ! flag_on nope; }
no_defaults_file_off() {
  ! run_in_sandbox bash -c 'OMV_FLAG_DEFAULTS=/nowhere/flags.lua; source "$1"; omv_flag_on weather' _ "$HELPER"
}

run_case 'should be on when a flag defaults to on' on_by_default
run_case 'should be off when a flag defaults to off' off_by_default
run_case 'should be off when its line says off' turned_off
run_case 'should be on when its line says on' turned_on
run_case 'should leave other flags alone when one is turned off' others_untouched
run_case 'should let the last line win' last_line_wins
run_case "should ignore a value that isn't on or off" ignores_bad_value
run_case 'should ignore a comment line' ignores_comment
run_case 'should treat an unknown flag as off' unknown_flag_off
run_case "should treat every flag as off when flags.lua can't be read" no_defaults_file_off
finish
