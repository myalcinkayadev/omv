#!/usr/bin/env bash
# Runs the aerospace.toml merge tests with luajit.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/aerospace_merge_test.lua" "$REPO_DIR"
