#!/usr/bin/env bash
# Runs the palette calculator tests with node. Skipped when node isn't installed: the
# calculator itself runs in the card's page, not in node.

source "$(dirname "$0")/lib.sh"

if ! command -v node >/dev/null 2>&1; then
  echo "ok   - skipped: node isn't installed"
  exit 0
fi

OMV_CALC="$REPO_DIR/hammerspoon/.hammerspoon/calc.js" node "$REPO_DIR/tests/calc_test.mjs"
