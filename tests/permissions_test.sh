#!/usr/bin/env bash
# Runs the permissions checklist tests with luajit. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/permissions_test.lua" "$REPO_DIR"
