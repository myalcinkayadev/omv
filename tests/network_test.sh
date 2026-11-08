#!/usr/bin/env bash
# Runs the network card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/network_test.lua" "$REPO_DIR"
