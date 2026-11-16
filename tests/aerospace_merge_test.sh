#!/usr/bin/env bash
# Runs the aerospace.toml merge tests with luajit, then checks the script run as a command.

source "$(dirname "$0")/lib.sh"

builds_through_symlink() {
  ln -s "$REPO_DIR/install/aerospace_merge.lua" "$SANDBOX/merge.lua"
  luajit "$SANDBOX/merge.lua" "$REPO_DIR/config/aerospace/.config/aerospace/aerospace.toml" "$SANDBOX/none" >/dev/null \
    || fail 'the merge failed through a symlink'
}

status=0
luajit "$REPO_DIR/tests/aerospace_merge_test.lua" "$REPO_DIR" || status=1
run_case 'should build when the merge is run through a symlink to it' builds_through_symlink
finish || status=1
exit "$status"
