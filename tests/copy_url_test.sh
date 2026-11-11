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

# The browser omv opens, from ~/.config/omv/apps.
choose_browser() {
  mkdir -p "$HOME_DIR/.config/omv"
  printf 'browser=%s\n' "$1" > "$HOME_DIR/.config/omv/apps"
}

asks_the_chosen_browser() {
  stub_helium
  choose_browser 'Google Chrome'
  run_in_sandbox "$COPY_URL"
  assert_called 'osascript -e tell application "Google Chrome" to get URL of active tab of front window'
}

asks_safari_for_its_current_tab() {
  stub_helium
  choose_browser Safari
  run_in_sandbox "$COPY_URL"
  assert_called 'osascript -e tell application "Safari" to get URL of current tab of front window'
}

asks_helium_without_a_choice() {
  stub_helium
  run_in_sandbox "$COPY_URL"
  assert_called 'osascript -e tell application "Helium" to get URL of active tab of front window'
}

run_case "should copy Helium's active tab URL to the clipboard" copies_active_tab_url
run_case 'should ask Helium for the URL of its active tab' asks_helium_for_active_tab
run_case 'should exit non-zero when Helium is not running' fails_when_helium_closed
run_case 'should not ask Helium when it is not running' skips_helium_when_closed
run_case 'should exit non-zero when Helium has no window' fails_without_window
run_case 'should ask the browser named in ~/.config/omv/apps' asks_the_chosen_browser
run_case 'should ask Safari for its current tab' asks_safari_for_its_current_tab
run_case 'should ask Helium when no browser is named' asks_helium_without_a_choice
finish
