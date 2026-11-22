#!/usr/bin/env bash
# Runs the section-editing tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/inifile_test.lua" "$REPO_DIR"
