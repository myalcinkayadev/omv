#!/usr/bin/env bash
# Behavior of share.sh: what it shares with AirDrop, and the helper it builds.

source "$(dirname "$0")/lib.sh"

readonly SHARE=$REPO_DIR/hammerspoon/.hammerspoon/share.sh

# osascript answers by what it's asked: the Finder selection from $SANDBOX/selection, a
# copied file from $SANDBOX/copied-file, a copied image when $SANDBOX/copied-image exists.
# swiftc "builds" the helper, which logs the paths it's given and exits with $SANDBOX/status.
stub_share_tools() {
  cat > "$STUB_DIR/osascript" <<STUB
#!/bin/sh
case "\$*" in
  *Finder*) cat "$SANDBOX/selection" 2>/dev/null ;;
  *furl*) cat "$SANDBOX/copied-file" 2>/dev/null || exit 1 ;;
  *PNGf*) [ -e "$SANDBOX/copied-image" ] || exit 1; echo "osascript png" >> "$CALL_LOG" ;;
esac
STUB
  cat > "$STUB_DIR/swiftc" <<STUB
#!/bin/sh
echo "swiftc \$*" >> "$CALL_LOG"
for last; do :; done
printf '#!/bin/sh\nfor path; do echo "share \$path" >> "%s"; done\nexit \$(cat "%s/status" 2>/dev/null || echo 0)\n' "$CALL_LOG" "$SANDBOX" > "\$last"
chmod +x "\$last"
STUB
  chmod +x "$STUB_DIR/osascript" "$STUB_DIR/swiftc"
}

shares_the_finder_selection() {
  stub_share_tools
  printf '/Users/me/a.pdf\n/Users/me/my photo.jpg\n' > "$SANDBOX/selection"
  run_in_sandbox "$SHARE" > /dev/null
  assert_called '^share airdrop$'
  assert_called '^share /Users/me/a.pdf$'
  assert_called '^share /Users/me/my photo.jpg$'
}

shares_a_copied_file_without_a_selection() {
  stub_share_tools
  echo '/Users/me/report.key' > "$SANDBOX/copied-file"
  run_in_sandbox "$SHARE" > /dev/null
  assert_called '^share /Users/me/report.key$'
}

shares_a_copied_image_as_a_file() {
  stub_share_tools
  touch "$SANDBOX/copied-image"
  run_in_sandbox "$SHARE" > /dev/null
  assert_called '^osascript png$'
  assert_called '^share .*\.png$'
}

says_when_there_is_nothing_to_share() {
  stub_share_tools
  assert_exit_nonzero run_in_sandbox "$SHARE"
  assert_not_called '^share'
}

builds_the_helper_once() {
  stub_share_tools
  echo '/Users/me/a.pdf' > "$SANDBOX/selection"
  run_in_sandbox "$SHARE" > /dev/null
  : > "$CALL_LOG"
  run_in_sandbox "$SHARE" > /dev/null
  assert_not_called '^swiftc'
}

fails_when_the_share_fails() {
  stub_share_tools
  echo '/Users/me/a.pdf' > "$SANDBOX/selection"
  echo 1 > "$SANDBOX/status"
  assert_exit_nonzero run_in_sandbox "$SHARE"
}

run_case 'should share the files selected in Finder' shares_the_finder_selection
run_case 'should share a copied file when Finder has no selection' shares_a_copied_file_without_a_selection
run_case 'should share a copied image as a file' shares_a_copied_image_as_a_file
run_case "should say there's nothing to share" says_when_there_is_nothing_to_share
run_case 'should build the helper once and reuse it' builds_the_helper_once
run_case 'should exit non-zero when the share fails' fails_when_the_share_fails
finish
