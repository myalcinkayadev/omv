#!/usr/bin/env bash
# Runs the pull request card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/prs_test.lua" "$REPO_DIR"
