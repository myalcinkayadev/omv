#!/usr/bin/env bash
# Behavior of the script behind Option+Shift+U, which copies Helium's current URL.

source "$(dirname "$0")/lib.sh"

readonly COPY_URL=$REPO_DIR/hammerspoon/.hammerspoon/copy-url.sh

# osascript answers with a URL, and pbcopy saves what it receives to $SANDBOX/clipboard.
stub_helium() {
  cat > "$STUB_DIR/osascript" <<EOF
#!/bin/sh
echo "osascript \$*" >> "$CALL_LOG"
echo 'https://example.com/page?q=1'
EOF
  cat > "$STUB_DIR/pbcopy" <<EOF
#!/bin/sh
cat > "$SANDBOX/clipboard"
EOF
  chmod +x "$STUB_DIR/osascript" "$STUB_DIR/pbcopy"
}

copies_active_tab_url() {
  stub_helium
  run_in_sandbox "$COPY_URL"
  [ "$(cat "$SANDBOX/clipboard")" = 'https://example.com/page?q=1' ] || fail "clipboard: $(cat "$SANDBOX/clipboard" 2>/dev/null)"
}

asks_helium_for_active_tab() {
  stub_helium
  run_in_sandbox "$COPY_URL"
  assert_called '^osascript .*URL of active tab of front window'
}

fails_when_helium_closed() {
  stub_helium
  stub pgrep 1
  assert_exit_nonzero run_in_sandbox "$COPY_URL"
}

skips_helium_when_closed() {
  stub_helium
  stub pgrep 1
  run_in_sandbox "$COPY_URL" >/dev/null 2>&1 || true
  assert_not_called '^osascript'
}

fails_without_window() {
  stub_helium
  stub osascript 1
  assert_exit_nonzero run_in_sandbox "$COPY_URL"
}

run_case "should copy Helium's active tab URL to the clipboard" copies_active_tab_url
run_case 'should ask Helium for the URL of its active tab' asks_helium_for_active_tab
run_case 'should exit non-zero when Helium is not running' fails_when_helium_closed
run_case 'should not ask Helium when it is not running' skips_helium_when_closed
run_case 'should exit non-zero when Helium has no window' fails_without_window
finish
