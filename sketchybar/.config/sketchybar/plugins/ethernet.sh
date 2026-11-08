#!/bin/sh
# Shows the Ethernet icon while a cable is connected, and opens the Ethernet card on a click.
# A port counts as connected when its link is up and it has an address. Wi-Fi, Bluetooth PAN and the
# Thunderbolt Bridge between two Macs are not cables to the network.

PATH="$PATH:/usr/sbin:/sbin"

if [ "${SENDER:-}" = mouse.clicked ]; then
  hs -c 'omvToggleEthernet()'
  exit 0
fi

wired_ports() {
  networksetup -listallhardwareports | awk '
    /^Hardware Port:/ { sub(/^Hardware Port: /, ""); port = $0 }
    /^Device:/ && port != "Wi-Fi" && port != "Bluetooth PAN" && port != "Thunderbolt Bridge" { print $2 }'
}

for device in $(wired_ports); do
  if ifconfig "$device" 2>/dev/null | grep -q 'status: active' && ipconfig getifaddr "$device" >/dev/null 2>&1; then
    sketchybar --set "$NAME" drawing=on icon="$(printf '\363\260\210\200')"
    exit 0
  fi
done

sketchybar --set "$NAME" drawing=off
