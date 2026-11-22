#!/usr/bin/env bash
# Runs the hs.ipc print guard tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/ipcguard_test.lua" "$REPO_DIR"
