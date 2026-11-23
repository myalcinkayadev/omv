#!/usr/bin/env bash
# Which workspaces the bar draws: those in the built aerospace.toml, so a workspace AeroSpace
# keeps only because a screen shows it, as on a third screen none is pinned to, isn't drawn.

source "$(dirname "$0")/lib.sh"

readonly SCRIPT=$REPO_DIR/config/sketchybar/.config/sketchybar/plugins/workspaces.sh
readonly TEXTS=$REPO_DIR/config/sketchybar/.config/sketchybar/plugins/workspace_texts.sh

# An aerospace that knows workspaces 1 to 8.
aerospace_knows_eight() {
  printf '#!/bin/sh\nprintf "1\\n2\\n3\\n4\\n5\\n6\\n7\\n8\\n"\n' > "$STUB_DIR/aerospace"
  chmod +x "$STUB_DIR/aerospace"
}

draws_the_built_workspaces_only() {
  aerospace_knows_eight
  mkdir -p "$HOME_DIR/.config/aerospace"
  printf "persistent-workspaces = ['1', '2', '5']\n" > "$HOME_DIR/.config/aerospace/aerospace.toml"
  local drawn
  drawn=$(run_in_sandbox "$SCRIPT")
  [ "$drawn" = '1 2 5' ] || fail "drew: $drawn"
}

asks_aerospace_without_a_built_file() {
  aerospace_knows_eight
  local drawn
  drawn=$(run_in_sandbox "$SCRIPT")
  [ "$drawn" = '1 2 3 4 5 6 7 8' ] || fail "drew: $drawn"
}

draws_seven_without_either() {
  stub aerospace 1
  local drawn
  drawn=$(run_in_sandbox "$SCRIPT")
  [ "$drawn" = '1 2 3 4 5 6 7' ] || fail "drew: $drawn"
}

# ~/.config/omv/workspaces with text.
workspaces_file() {
  mkdir -p "$HOME_DIR/.config/omv"
  printf '%b' "$1" > "$HOME_DIR/.config/omv/workspaces"
}

names_the_named_workspaces() {
  workspaces_file 'bar = {number}: {name}\n[workspace 1]\nname = Code\n[workspace 2]\n'
  local texts
  texts=$(run_in_sandbox "$TEXTS")
  [ "$texts" = "$(printf '1\t1: Code')" ] || fail "gave: $texts"
}

names_nothing_without_names() {
  workspaces_file '[workspace 1]\n'
  local texts
  texts=$(run_in_sandbox "$TEXTS")
  [ -z "$texts" ] || fail "gave: $texts"
}

names_nothing_without_a_file() {
  local texts
  texts=$(run_in_sandbox "$TEXTS")
  [ -z "$texts" ] || fail "gave: $texts"
}

run_case "should draw only the workspaces in the built aerospace.toml" draws_the_built_workspaces_only
run_case "should draw the workspaces AeroSpace has without a built file" asks_aerospace_without_a_built_file
run_case "should draw today's seven without either" draws_seven_without_either
run_case "should give the bar's text for the named workspaces" names_the_named_workspaces
run_case "should give no text when no workspace has a name" names_nothing_without_names
run_case "should give no text without a workspaces file" names_nothing_without_a_file
finish
