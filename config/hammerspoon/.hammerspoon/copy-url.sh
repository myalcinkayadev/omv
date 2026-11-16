#!/bin/sh
# Usage: copy-url.sh
# Copies the URL of the browser's active tab: the browser named in ~/.config/omv/apps, else
# Helium. On failure it prints why, for Hammerspoon to show. The first run makes macOS ask
# to let Hammerspoon control the browser. Safari calls its tab "current"; Helium, Chrome
# and the other Chromium browsers call it "active".

config="$HOME/.config/omv/apps"
browser=$(sed -n 's/^[[:space:]]*browser[[:space:]]*=[[:space:]]*//p' "$config" 2>/dev/null | tail -n 1 | sed 's/[[:space:]]*$//')
browser=${browser:-Helium}

# The name goes into AppleScript, so a quote or backslash could change what it runs.
case $browser in
  *'"'* | *'\'*)
    echo "The browser's name in $config can't hold quotes" >&2
    exit 1
    ;;
esac

if ! pgrep -x "$browser" >/dev/null; then
  echo "$browser isn't open" >&2
  exit 1
fi

case $browser in
  Safari) tab='current tab' ;;
  *) tab='active tab' ;;
esac

url=$(osascript -e "tell application \"$browser\" to get URL of $tab of front window" 2>/dev/null)
if [ -z "$url" ]; then
  echo "$browser has no window" >&2
  exit 1
fi

printf '%s' "$url" | pbcopy
