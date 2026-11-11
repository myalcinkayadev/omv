#!/usr/bin/env bash
# Runs the Bluetooth card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/bluetooth_test.lua" "$REPO_DIR"
