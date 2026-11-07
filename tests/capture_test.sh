#!/usr/bin/env bash
# Behavior of the capture menu: its Lua rows, and the script behind text and color.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/capture_test.lua" "$REPO_DIR" || failed=$((failed + 1))

readonly CAPTURE=$REPO_DIR/hammerspoon/.hammerspoon/capture.sh

# screencapture saves a picture unless $SANDBOX/cancel exists. swiftc "builds" the helper
# by copying $SANDBOX/helper, whose output each case sets. pbcopy saves to $SANDBOX/clipboard.
stub_capture_tools() {
  cat > "$STUB_DIR/screencapture" <<STUB
#!/bin/sh
echo "screencapture \$*" >> "$CALL_LOG"
[ -e "$SANDBOX/cancel" ] && exit 1
for last; do :; done
echo picture > "\$last"
STUB
  cat > "$STUB_DIR/swiftc" <<STUB
#!/bin/sh
echo "swiftc \$*" >> "$CALL_LOG"
for last; do :; done
cp "$SANDBOX/helper" "\$last"
chmod +x "\$last"
STUB
  cat > "$STUB_DIR/pbcopy" <<STUB
#!/bin/sh
cat > "$SANDBOX/clipboard"
STUB
  chmod +x "$STUB_DIR/screencapture" "$STUB_DIR/swiftc" "$STUB_DIR/pbcopy"
  helper_prints 'hello world'
}

helper_prints() {
  printf '#!/bin/sh\nprintf %%s %q\n' "$1" > "$SANDBOX/helper"
}

builds_helper_when_missing() {
  stub_capture_tools
  run_in_sandbox "$CAPTURE" text
  assert_called '^swiftc .*capture\.swift'
}

reuses_cached_helper() {
  stub_capture_tools
  mkdir -p "$HOME_DIR/.cache/omv"
  cp "$SANDBOX/helper" "$HOME_DIR/.cache/omv/capture"
  chmod +x "$HOME_DIR/.cache/omv/capture"
  run_in_sandbox "$CAPTURE" text
  assert_not_called '^swiftc'
}

copies_recognized_text() {
  stub_capture_tools
  run_in_sandbox "$CAPTURE" text
  [ "$(cat "$SANDBOX/clipboard")" = 'hello world' ] || fail "clipboard: $(cat "$SANDBOX/clipboard" 2>/dev/null)"
}

leaves_clipboard_when_cancelled() {
  stub_capture_tools
  touch "$SANDBOX/cancel"
  run_in_sandbox "$CAPTURE" text 2>/dev/null || true
  if [ -e "$SANDBOX/clipboard" ]; then
    fail 'clipboard was written'
  fi
}

fails_when_cancelled() {
  stub_capture_tools
  touch "$SANDBOX/cancel"
  assert_exit_nonzero run_in_sandbox "$CAPTURE" text
}

fails_when_no_text_found() {
  stub_capture_tools
  helper_prints ''
  assert_exit_nonzero run_in_sandbox "$CAPTURE" text
}

copies_picked_color() {
  stub_capture_tools
  helper_prints '#8D8D8D'
  run_in_sandbox "$CAPTURE" color
  [ "$(cat "$SANDBOX/clipboard")" = '#8D8D8D' ] || fail "clipboard: $(cat "$SANDBOX/clipboard" 2>/dev/null)"
}

rejects_unknown_mode() {
  stub_capture_tools
  assert_exit_nonzero run_in_sandbox "$CAPTURE" sideways
}

run_case 'should build the helper when there is no cached copy' builds_helper_when_missing
run_case 'should use the cached helper when it is newer than the source' reuses_cached_helper
run_case 'should copy the recognized text' copies_recognized_text
run_case 'should leave the clipboard alone when the region is cancelled' leaves_clipboard_when_cancelled
run_case 'should exit non-zero when the region is cancelled' fails_when_cancelled
run_case 'should exit non-zero when no text is found' fails_when_no_text_found
run_case 'should copy the picked color' copies_picked_color
run_case 'should exit non-zero when given an unknown mode' rejects_unknown_mode
finish
