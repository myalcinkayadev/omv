#!/usr/bin/env bash
# Runs the snippets tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/snippets_test.lua" "$REPO_DIR"
