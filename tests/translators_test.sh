#!/usr/bin/env bash
# Runs the translation service tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/translators_test.lua" "$REPO_DIR"
