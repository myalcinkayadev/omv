#!/bin/sh
# Usage: new-window.sh [command]
# Opens a window in the running Ghostty, so windows share one process.
# Ghostty has no +new-window on macOS, so this goes through its AppleScript support.
# A command goes through the shell because Ghostty keeps windows open after an AppleScript
# "command" exits, even with "wait after command" off. Using exec closes the window with it.

command=${1:-}

# -a counts ancestors too: run from a Ghostty terminal, plain pgrep skips Ghostty itself.
if ! pgrep -ax ghostty >/dev/null; then
  [ -n "$command" ] && exec open -a Ghostty --args -e "$command"
  exec open -a Ghostty
fi

if [ -z "$command" ]; then
  exec osascript -e 'tell application id "com.mitchellh.ghostty" to new window'
fi

exec osascript \
  -e 'on run argv' \
  -e 'tell application id "com.mitchellh.ghostty"' \
  -e 'set windowConfig to new surface configuration' \
  -e 'set initial input of windowConfig to "exec " & item 1 of argv & linefeed' \
  -e 'new window with configuration windowConfig' \
  -e 'end tell' \
  -e 'end run' \
  "$command"
