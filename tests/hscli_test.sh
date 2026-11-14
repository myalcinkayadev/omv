#!/usr/bin/env bash
# Runs the hs command install tests with luajit. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/hscli_test.lua" "$REPO_DIR"
