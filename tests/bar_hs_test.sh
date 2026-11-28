#!/usr/bin/env bash
# Behavior of the bar's hs.sh: it runs Lua in Hammerspoon and never waits on it for long.

source "$(dirname "$0")/lib.sh"

readonly HS_SCRIPT=$REPO_DIR/config/sketchybar/.config/sketchybar/hs.sh

passes_the_lua_to_hs() {
  stub hs
  run_in_sandbox "$HS_SCRIPT" 'omvToggleCalendar()'
  assert_called "^hs -t 2 -c omvToggleCalendar\(\)$"
}

gives_up_on_a_call_hammerspoon_never_answers() {
  own_stub hs
  printf '#!/bin/sh\nsleep 30\n' > "$STUB_DIR/hs"
  chmod +x "$STUB_DIR/hs"
  local started=$SECONDS
  run_in_sandbox OMV_HS_SECONDS=1 "$HS_SCRIPT" 'omvToggleCalendar()' || true
  [ $((SECONDS - started)) -le 3 ]
}

doesnt_wait_on_its_input() {
  # A stub that reads its input to the end: given the caller's pipe, open for a minute, it
  # would wait until the alarm ends it, 142; given /dev/null, it ends at once. The alarm is
  # long, since macOS checking a new executable under the whole suite's load takes seconds.
  shared_stub hs <<'STUB'
#!/bin/sh
cat >/dev/null
STUB
  run_in_sandbox OMV_HS_SECONDS=30 "$HS_SCRIPT" 'omvToggleCalendar()' < <(sleep 60)
}

run_case "should pass the Lua to hs with a timeout" passes_the_lua_to_hs
run_case "should give up on a call Hammerspoon never answers" gives_up_on_a_call_hammerspoon_never_answers
run_case "should not wait on its own input, which hs would read as more Lua" doesnt_wait_on_its_input
finish
