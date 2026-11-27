#!/usr/bin/env bash
# Runs the camera and mic in-use tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/inuse_test.lua" "$REPO_DIR"
