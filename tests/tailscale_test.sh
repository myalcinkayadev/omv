#!/usr/bin/env bash
# Runs the Tailscale card tests. Hammerspoon and Tailscale are not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/tailscale_test.lua" "$REPO_DIR"
