#!/usr/bin/env bash
# Behavior of the lyrics window: the Lua side, and lyrics-window.sh, which builds and runs
# the window helper.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/lyrics_test.lua" "$REPO_DIR" || failed=$((failed + 1))

readonly LYRICS_WINDOW=$REPO_DIR/hammerspoon/.hammerspoon/lyrics-window.sh

app() {
  echo "$HOME_DIR/.cache/omv/Lyrics.app"
}

# swiftc "builds" the helper by copying $SANDBOX/helper, which echoes what it reads, so a
# test can see that Hammerspoon's commands reach it.
stub_build() {
  cat > "$STUB_DIR/swiftc" <<STUB
#!/bin/sh
echo "swiftc \$*" >> "$CALL_LOG"
for last; do :; done
cp "$SANDBOX/helper" "\$last"
chmod +x "\$last"
STUB
  chmod +x "$STUB_DIR/swiftc"
  stub codesign
  printf '#!/bin/sh\necho "helper $*" >> "%s"\ncat\n' "$CALL_LOG" > "$SANDBOX/helper"
}

window() {
  printf '%s' "${1:-}" | run_in_sandbox "$LYRICS_WINDOW"
}

builds_helper_into_a_bundle() {
  stub_build
  window > /dev/null
  assert_called "^swiftc -O .*/lyrics-window.swift -o $(app)/Contents/MacOS/lyrics-window$"
}

names_the_bundle_for_aerospace() {
  stub_build
  window > /dev/null
  grep -q '<string>dev.omv.lyrics</string>' "$(app)/Contents/Info.plist" || fail 'no bundle identifier for the AeroSpace rule'
}

keeps_out_of_the_dock() {
  stub_build
  window > /dev/null
  grep -q '<key>LSUIElement</key><true/>' "$(app)/Contents/Info.plist" || fail 'the helper would show in the Dock'
}

signs_the_bundle() {
  stub_build
  window > /dev/null
  assert_called "^codesign --force --sign - $(app)$"
}

skips_build_when_helper_is_fresh() {
  stub_build
  window > /dev/null
  : > "$CALL_LOG"
  window > /dev/null
  assert_not_called '^swiftc'
}

passes_commands_to_the_helper() {
  stub_build
  [ "$(window '{"js":"omvAt(3)"}')" = '{"js":"omvAt(3)"}' ] || fail 'the helper never got the command'
}

fails_when_the_build_fails() {
  stub_build
  stub swiftc 1
  assert_exit_nonzero window
}

run_case "should build the helper into an app bundle" builds_helper_into_a_bundle
run_case "should give the bundle the identifier AeroSpace's rule matches" names_the_bundle_for_aerospace
run_case "should keep the helper out of the Dock" keeps_out_of_the_dock
run_case "should sign the bundle" signs_the_bundle
run_case "should skip the build when the helper is newer than its source" skips_build_when_helper_is_fresh
run_case "should pass Hammerspoon's commands to the helper" passes_commands_to_the_helper
run_case "should fail when the helper can't be built" fails_when_the_build_fails
finish
