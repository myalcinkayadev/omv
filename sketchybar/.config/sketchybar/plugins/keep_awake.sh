#!/bin/sh
# Keeps the display and system awake while the coffee icon shows.
# Option+Shift+I sends keep_awake_toggle, and clicking the icon also toggles.
# Only the caffeinate saved here is checked or stopped, never one another tool started.

pid_file="$HOME/.local/state/omv/keep-awake.pid"

is_on() {
  [ -r "$pid_file" ] && pgrep -F "$pid_file" -x caffeinate >/dev/null 2>&1
}

turn_on() {
  mkdir -p "$(dirname "$pid_file")"
  nohup caffeinate -di >/dev/null 2>&1 &
  echo "$!" > "$pid_file"
}

turn_off() {
  pkill -F "$pid_file" -x caffeinate
  rm -f "$pid_file"
}

show() {
  sketchybar --set "$NAME" drawing="$1"
}

case "${SENDER:-}" in
  keep_awake_toggle | mouse.clicked)
    if is_on; then
      turn_off
      show off
    else
      turn_on
      show on
    fi
    ;;
  *)
    if is_on; then show on; else show off; fi
    ;;
esac
