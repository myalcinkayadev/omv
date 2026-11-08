#!/usr/bin/env bash
# Compiles Hammerspoon's init.lua. Lua allows 200 locals in one chunk, and passing that
# stops the whole config from loading, so the suite catches it before Hammerspoon does.

source "$(dirname "$0")/lib.sh"

compiles_init() {
  luajit -bl "$REPO_DIR/hammerspoon/.hammerspoon/init.lua" >/dev/null 2>"$SANDBOX/error" || fail "$(cat "$SANDBOX/error")"
}

run_case "should compile init.lua within Lua's limit of 200 locals" compiles_init
finish
