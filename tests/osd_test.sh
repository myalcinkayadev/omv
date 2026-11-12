#!/usr/bin/env bash
# Runs the volume and brightness pop-up tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/osd_test.lua" "$REPO_DIR"
