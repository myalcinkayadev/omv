#!/usr/bin/env bash
# Runs the Agents card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/agents_test.lua" "$REPO_DIR"
