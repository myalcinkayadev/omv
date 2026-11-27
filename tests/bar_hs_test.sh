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

run_case "should pass the Lua to hs with a timeout" passes_the_lua_to_hs
run_case "should give up on a call Hammerspoon never answers" gives_up_on_a_call_hammerspoon_never_answers
finish
