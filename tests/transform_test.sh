#!/usr/bin/env bash
# Runs the palette's clipboard action tests with node. Skipped when node isn't installed: the
# actions themselves run in the card's page, not in node.

source "$(dirname "$0")/lib.sh"

if ! command -v node >/dev/null 2>&1; then
  echo "ok   - skipped: node isn't installed"
  exit 0
fi

OMV_TRANSFORM="$REPO_DIR/config/hammerspoon/transform.js" node "$REPO_DIR/tests/transform_test.mjs"
