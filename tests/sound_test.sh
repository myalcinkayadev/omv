#!/usr/bin/env bash
# Runs the Sound card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/sound_test.lua" "$REPO_DIR"
