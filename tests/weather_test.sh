#!/usr/bin/env bash
# Runs the weather card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/weather_test.lua" "$REPO_DIR"
