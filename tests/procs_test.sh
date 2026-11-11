#!/usr/bin/env bash
# Runs the process card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/procs_test.lua" "$REPO_DIR"
