#!/usr/bin/env bash
# Runs the OpenCode plugin and pi extension tests with node, against a stub hook.
# Skipped when node isn't installed, since only those agents need it.

source "$(dirname "$0")/lib.sh"

if ! command -v node >/dev/null 2>&1; then
  echo "ok   - skipped: node isn't installed"
  exit 0
fi

new_sandbox
cat > "$STUB_DIR/hook" <<STUB
#!/bin/sh
printf '%s\t%s\n' "\$*" "\$(cat)" >> "$SANDBOX/hook.log"
STUB
chmod +x "$STUB_DIR/hook"

OMV_AGENT_HOOK="$STUB_DIR/hook" OMV_TEST_LOG="$SANDBOX/hook.log" \
  OMV_OPENCODE_PLUGIN="$REPO_DIR/opencode/.config/opencode/plugins/omv-agent-state.js" \
  OMV_PI_EXTENSION="$REPO_DIR/pi/.pi/agent/extensions/omv-agent-state.ts" \
  node --experimental-strip-types --no-warnings "$REPO_DIR/tests/agent_plugins_test.mjs"
