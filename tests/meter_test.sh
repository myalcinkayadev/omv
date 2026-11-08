#!/usr/bin/env bash
# Behavior of meter.sh, which builds the mic level helper and starts or stops it.

source "$(dirname "$0")/lib.sh"

readonly METER=$REPO_DIR/hammerspoon/.hammerspoon/meter.sh

app() {
  echo "$HOME_DIR/.cache/omv/Meter.app"
}

# swiftc "builds" the helper by writing a script that does nothing.
stub_meter_tools() {
  cat > "$STUB_DIR/swiftc" <<STUB
#!/bin/sh
echo "swiftc \$*" >> "$CALL_LOG"
for last; do :; done
printf '#!/bin/sh\nexit 0\n' > "\$last"
chmod +x "\$last"
STUB
  chmod +x "$STUB_DIR/swiftc"
  stub codesign
}

meter() {
  run_in_sandbox "$METER" "$@"
}

builds_helper_into_a_bundle() {
  stub_meter_tools
  meter start "$SANDBOX/level"
  assert_called "^swiftc -O .*/meter.swift -o $(app)/Contents/MacOS/meter$"
}

asks_for_microphone_access_by_name() {
  stub_meter_tools
  meter start "$SANDBOX/level"
  grep -q 'NSMicrophoneUsageDescription' "$(app)/Contents/Info.plist" || fail 'no usage description'
}

stays_out_of_the_dock() {
  stub_meter_tools
  meter start "$SANDBOX/level"
  grep -q '<key>LSUIElement</key><true/>' "$(app)/Contents/Info.plist" || fail 'the helper would show in the Dock'
}

signs_the_bundle() {
  stub_meter_tools
  meter start "$SANDBOX/level"
  assert_called "^codesign --force --sign - $(app)$"
}

skips_build_when_helper_is_fresh() {
  stub_meter_tools
  meter start "$SANDBOX/level"
  : > "$CALL_LOG"
  meter start "$SANDBOX/level"
  assert_not_called '^swiftc'
}

starts_helper_hidden_without_waiting() {
  stub_meter_tools
  meter start "$SANDBOX/level"
  assert_called "^open -n -g -j $(app) --args $SANDBOX/level$"
}

stops_helper_by_name() {
  meter stop
  assert_called "^pkill -f $(app)/Contents/MacOS/meter$"
}

fails_when_the_build_fails() {
  stub_meter_tools
  stub swiftc 1
  assert_exit_nonzero meter start "$SANDBOX/level"
}

says_why_when_the_build_fails() {
  stub_meter_tools
  stub swiftc 1
  meter start "$SANDBOX/level" 2>&1 | grep -q "Couldn't build the meter helper" || fail 'no reason given'
}

fails_without_a_command() {
  assert_exit_nonzero meter
}

run_case "should build the helper into an app bundle" builds_helper_into_a_bundle
run_case "should say why it needs the microphone" asks_for_microphone_access_by_name
run_case "should keep the helper out of the Dock" stays_out_of_the_dock
run_case "should sign the bundle" signs_the_bundle
run_case "should skip the build when the helper is newer than its source" skips_build_when_helper_is_fresh
run_case "should start the helper hidden without waiting for it" starts_helper_hidden_without_waiting
run_case "should stop the helper by its name" stops_helper_by_name
run_case "should fail when the helper can't be built" fails_when_the_build_fails
run_case "should say why when the helper can't be built" says_why_when_the_build_fails
run_case "should fail when given no command" fails_without_a_command
finish
