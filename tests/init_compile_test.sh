#!/usr/bin/env bash
# Compiles Hammerspoon's init.lua and every module. Lua allows 200 locals in one chunk, and
# passing that stops the whole config from loading, so the suite catches it before Hammerspoon
# does. init.lua only wires the features together, so it stays far below that limit.

source "$(dirname "$0")/lib.sh"

readonly HAMMERSPOON=$REPO_DIR/hammerspoon/.hammerspoon
readonly INIT_LOCALS_LIMIT=60

compiles_init() {
  luajit -bl "$HAMMERSPOON/init.lua" >/dev/null 2>"$SANDBOX/error" || fail "$(cat "$SANDBOX/error")"
}

compiles_every_module() {
  local module
  while IFS= read -r module; do
    luajit -bl "$module" >/dev/null 2>"$SANDBOX/error" || fail "$(cat "$SANDBOX/error")"
  done < <(find "$HAMMERSPOON" -name '*.lua')
}

# Counts the names each top-level local line declares: "local a, b = ..." is two.
keeps_init_locals_low() {
  local count
  count=$(grep -E '^local ' "$HAMMERSPOON/init.lua" \
    | sed -E 's/^local (function )?//; s/[=(].*//' \
    | tr ',' '\n' | grep -c '[[:alnum:]]')
  [ "$count" -lt "$INIT_LOCALS_LIMIT" ] || fail "init.lua has $count top-level locals, the limit is $INIT_LOCALS_LIMIT"
}

run_case "should compile init.lua within Lua's limit of 200 locals" compiles_init
run_case "should compile every Hammerspoon module" compiles_every_module
run_case "should keep init.lua under $INIT_LOCALS_LIMIT top-level locals" keeps_init_locals_low
finish
