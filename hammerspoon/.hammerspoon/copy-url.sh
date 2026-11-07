#!/bin/sh
# Usage: copy-url.sh
# Copies the URL of Helium's active tab. On failure it prints why, for Hammerspoon to show.
# The first run makes macOS ask to let Hammerspoon control Helium.

if ! pgrep -x Helium >/dev/null; then
  echo "Helium isn't open" >&2
  exit 1
fi

url=$(osascript -e 'tell application id "net.imput.helium" to get URL of active tab of front window' 2>/dev/null)
if [ -z "$url" ]; then
  echo "Helium has no window" >&2
  exit 1
fi

printf '%s' "$url" | pbcopy
