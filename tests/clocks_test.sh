#!/usr/bin/env bash
# Runs the world clocks tests: the file and rows with luajit, the times with node. The node
# half is skipped when node isn't installed: the times themselves are worked out in the card's page.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/clocks_test.lua" "$REPO_DIR" || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo "ok   - skipped: node isn't installed"
  exit 0
fi

OMV_CLOCKS="$REPO_DIR/config/hammerspoon/clocks.js" node "$REPO_DIR/tests/clocks_test.mjs"
