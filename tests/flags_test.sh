#!/usr/bin/env bash
# Runs the feature flag tests with luajit. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/flags_test.lua" "$REPO_DIR"
