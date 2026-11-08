#!/usr/bin/env bash
# Behavior of today's events: the Lua side, and agenda.sh, which builds and runs the helper.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/agenda_test.lua" "$REPO_DIR" || failed=$((failed + 1))

readonly AGENDA=$REPO_DIR/hammerspoon/.hammerspoon/agenda.sh

app() {
  echo "$HOME_DIR/.cache/omv/Agenda.app"
}

# swiftc "builds" the helper by copying $SANDBOX/helper. open runs the bundle's helper with
# the arguments after --args, the way LaunchServices would.
stub_agenda_tools() {
  cat > "$STUB_DIR/swiftc" <<STUB
#!/bin/sh
echo "swiftc \$*" >> "$CALL_LOG"
for last; do :; done
cp "$SANDBOX/helper" "\$last"
chmod +x "\$last"
STUB
  cat > "$STUB_DIR/open" <<STUB
#!/bin/sh
echo "open \$*" >> "$CALL_LOG"
bundle=
while [ \$# -gt 0 ]; do
  case \$1 in
    --args) shift; break ;;
    -*) ;;
    *) bundle=\$1 ;;
  esac
  shift
done
"\$bundle/Contents/MacOS/agenda" "\$@"
STUB
  chmod +x "$STUB_DIR/swiftc" "$STUB_DIR/open"
  stub codesign
  helper_writes '1\t2\t0\tStandup\n'
}

helper_writes() {
  printf '#!/bin/sh\nprintf %q > "$1"\n' "$1" > "$SANDBOX/helper"
}

agenda() {
  run_in_sandbox "$AGENDA"
}

builds_helper_into_a_bundle() {
  stub_agenda_tools
  agenda > /dev/null
  assert_called "^swiftc -O .*/agenda.swift -o $(app)/Contents/MacOS/agenda$"
  [ -x "$(app)/Contents/MacOS/agenda" ] || fail 'no helper was built'
}

asks_for_calendar_access_by_name() {
  stub_agenda_tools
  agenda > /dev/null
  grep -q 'NSCalendarsFullAccessUsageDescription' "$(app)/Contents/Info.plist" || fail 'no usage description'
  grep -q '<key>LSUIElement</key><true/>' "$(app)/Contents/Info.plist" || fail 'the helper would show in the Dock'
}

signs_the_bundle() {
  stub_agenda_tools
  agenda > /dev/null
  assert_called "^codesign --force --sign - $(app)$"
}

skips_build_when_helper_is_fresh() {
  stub_agenda_tools
  agenda > /dev/null
  : > "$CALL_LOG"
  agenda > /dev/null
  assert_not_called '^swiftc'
}

opens_helper_in_the_background_and_waits() {
  stub_agenda_tools
  agenda > /dev/null
  assert_called "^open -W -g -j $(app) --args $HOME_DIR/.cache/omv/agenda$"
}

prints_the_events() {
  stub_agenda_tools
  [ "$(agenda)" = "$(printf '1\t2\t0\tStandup')" ] || fail "unexpected output: $(agenda)"
}

prints_denied() {
  stub_agenda_tools
  helper_writes 'denied\n'
  [ "$(agenda)" = denied ] || fail "unexpected output: $(agenda)"
}

fails_when_the_helper_writes_nothing() {
  stub_agenda_tools
  printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/helper"
  assert_exit_nonzero agenda
}

never_prints_events_left_from_before() {
  stub_agenda_tools
  agenda > /dev/null
  printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/helper"
  touch -d '2000-01-01' "$(app)/Contents/MacOS/agenda" 2>/dev/null || touch -t 200001010000 "$(app)/Contents/MacOS/agenda"
  assert_exit_nonzero agenda
}

fails_when_the_build_fails() {
  stub_agenda_tools
  stub swiftc 1
  assert_exit_nonzero agenda
}

run_case "should build the helper into an app bundle" builds_helper_into_a_bundle
run_case "should say why it needs Calendar access, and stay out of the Dock" asks_for_calendar_access_by_name
run_case "should sign the bundle" signs_the_bundle
run_case "should skip the build when the helper is newer than its source" skips_build_when_helper_is_fresh
run_case "should open the helper in the background and wait for it" opens_helper_in_the_background_and_waits
run_case "should print the events the helper wrote" prints_the_events
run_case "should print denied when access was refused" prints_denied
run_case "should fail when the helper writes nothing" fails_when_the_helper_writes_nothing
run_case "should never print events left from an earlier run" never_prints_events_left_from_before
run_case "should fail when the helper can't be built" fails_when_the_build_fails
finish
