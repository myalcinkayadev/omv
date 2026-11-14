#!/usr/bin/env bash
# Behavior of the bar's Bluetooth item: the icon shows whether Bluetooth is on, and a click
# opens the Bluetooth card. The state comes from Hammerspoon, which has Bluetooth access;
# hs is a stub that answers as Hammerspoon would.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/bluetooth.sh

# hs -c prints any extension it loads, then the answer: 1, 0, or nothing without access.
stub_hammerspoon() {
  cat > "$STUB_DIR/hs" <<STUB
#!/bin/sh
echo "hs \$*" >> "$CALL_LOG"
echo '-- Loading extension: timer'
printf '%s\n' '$1'
STUB
  chmod +x "$STUB_DIR/hs"
}

run_plugin() {
  run_in_sandbox NAME=bluetooth "$@" "$PLUGIN"
}

shows_on_icon() {
  stub_hammerspoon 1
  run_plugin SENDER=routine
  assert_called "^sketchybar --set bluetooth drawing=on icon=$(printf '\363\260\202\257')$"
}

shows_off_icon() {
  stub_hammerspoon 0
  run_plugin SENDER=routine
  assert_called "^sketchybar --set bluetooth drawing=on icon=$(printf '\363\260\202\262')$"
}

hides_without_access() {
  stub_hammerspoon ''
  run_plugin SENDER=routine
  assert_called '^sketchybar --set bluetooth drawing=off$'
}

# hs fails like this when Hammerspoon isn't running. A stub, so a real hs on this Mac never answers.
hides_without_hammerspoon() {
  cat > "$STUB_DIR/hs" <<'STUB'
#!/bin/sh
echo "error: can't access Hammerspoon message port Hammerspoon; is it running with the ipc module loaded?" >&2
exit 69
STUB
  chmod +x "$STUB_DIR/hs"
  run_plugin SENDER=routine
  assert_called '^sketchybar --set bluetooth drawing=off$'
}

# hs can wait for Hammerspoon forever, as during a reload. Each timer tick would then leave
# one more hs behind, until Hammerspoon stops answering any of them.
stub_hanging_hammerspoon() {
  cat > "$STUB_DIR/hs" <<STUB
#!/bin/sh
echo \$\$ > "$SANDBOX/hs.pid"
exec sleep 30
STUB
  chmod +x "$STUB_DIR/hs"
}

# The plugin gives hs 1 second here; 15 leaves room for a busy machine.
run_with_hanging_hammerspoon() {
  stub_hanging_hammerspoon
  run_plugin OMV_HS_SECONDS=1 SENDER=routine &
  plugin=$!
  for _ in $(seq 15); do kill -0 "$plugin" 2>/dev/null || break; sleep 1; done
}

hides_when_hammerspoon_hangs() {
  run_with_hanging_hammerspoon
  assert_called '^sketchybar --set bluetooth drawing=off$'
}

leaves_no_hanging_hs() {
  run_with_hanging_hammerspoon
  # On a busy machine hs can be stopped before it writes its pid: then none is left.
  [ -f "$SANDBOX/hs.pid" ] || return 0
  hs_pid=$(cat "$SANDBOX/hs.pid")
  if kill -0 "$hs_pid" 2>/dev/null; then kill "$hs_pid"; return 1; fi
}

asks_hammerspoon() {
  stub_hammerspoon 1
  run_plugin SENDER=routine
  assert_called "^hs -c return omvBluetoothPower\\(\\)$"
}

opens_card_on_click() {
  stub hs
  run_plugin SENDER=mouse.clicked
  assert_called '^hs -c omvToggleBluetooth\(\)$'
}

run_case 'should show the on icon when Hammerspoon says Bluetooth is on' shows_on_icon
run_case "should show the off icon when Hammerspoon says it's off" shows_off_icon
run_case "should hide the icon when Hammerspoon can't read Bluetooth" hides_without_access
run_case "should hide the icon when Hammerspoon isn't running" hides_without_hammerspoon
run_case 'should hide the icon when Hammerspoon hangs' hides_when_hammerspoon_hangs
run_case 'should leave no hs waiting when Hammerspoon hangs' leaves_no_hanging_hs
run_case 'should ask Hammerspoon for the state' asks_hammerspoon
run_case 'should open the Bluetooth card on a click' opens_card_on_click
finish
