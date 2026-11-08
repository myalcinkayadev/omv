#!/usr/bin/env bash
# Behavior of the bar's Ethernet item: shown only while a cable is connected.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/ethernet.sh

PORTS_WITH_LAN='Hardware Port: Wi-Fi
Device: en0
Ethernet Address: aa:bb:cc:dd:ee:ff

Hardware Port: Thunderbolt Bridge
Device: bridge0
Ethernet Address: N/A

Hardware Port: USB 10/100/1000 LAN
Device: en5
Ethernet Address: 00:e0:4c:68:01:02'

# networksetup prints $SANDBOX/ports. ipconfig getifaddr answers only for devices
# listed in $SANDBOX/addresses, as "<device> <ip>".
stub_network() {
  printf '%s\n' "$1" > "$SANDBOX/ports"
  printf '%s\n' "$2" > "$SANDBOX/addresses"
  cat > "$STUB_DIR/networksetup" <<STUB
#!/bin/sh
cat "$SANDBOX/ports"
STUB
  cat > "$STUB_DIR/ipconfig" <<STUB
#!/bin/sh
echo "ipconfig \$*" >> "$CALL_LOG"
awk -v d="\$2" '\$1 == d { print \$2; found = 1 } END { exit !found }' "$SANDBOX/addresses"
STUB
  chmod +x "$STUB_DIR/networksetup" "$STUB_DIR/ipconfig"
}

draw() {
  run_in_sandbox NAME=ethernet SENDER=routine "$PLUGIN"
}

shows_item_with_cable() {
  stub_network "$PORTS_WITH_LAN" "en5 192.168.1.31"
  draw
  assert_called '^sketchybar --set ethernet drawing=on'
}

hides_item_when_unplugged() {
  stub_network "$PORTS_WITH_LAN" "en0 192.168.1.24"
  draw
  assert_called '^sketchybar --set ethernet drawing=off'
}

hides_item_with_only_wifi() {
  stub_network 'Hardware Port: Wi-Fi
Device: en0' "en0 192.168.1.24"
  draw
  assert_called '^sketchybar --set ethernet drawing=off'
}

ignores_thunderbolt_bridge() {
  stub_network "$PORTS_WITH_LAN" "bridge0 169.254.1.2"
  draw
  assert_called '^sketchybar --set ethernet drawing=off'
}

opens_card_on_click() {
  stub hs
  run_in_sandbox NAME=ethernet SENDER=mouse.clicked "$PLUGIN"
  assert_called "^hs -c omvToggleEthernet\(\)$"
}

run_case "should show the item when a LAN port has an address" shows_item_with_cable
run_case "should hide the item when the LAN port has no address" hides_item_when_unplugged
run_case "should hide the item when there is only Wi-Fi" hides_item_with_only_wifi
run_case "should hide the item when only the Thunderbolt Bridge has an address" ignores_thunderbolt_bridge
run_case "should open the Ethernet card on a click" opens_card_on_click
finish
