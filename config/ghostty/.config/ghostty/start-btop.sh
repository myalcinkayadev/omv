#!/bin/sh
# Opens btop unless one is already running, so restarting AeroSpace adds no duplicate.

pgrep -x btop >/dev/null && exit 0
exec "$(dirname "$0")/new-window.sh" /opt/homebrew/bin/btop
