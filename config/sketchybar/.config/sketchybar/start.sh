#!/bin/sh
# Starts SketchyBar unless one is running; AeroSpace runs it when it starts, and omv doctor --fix
# to restart the bar. Checking and starting were two steps, so two quick starts, such as
# AeroSpace starting again right after Accessibility was allowed, both found no bar and left
# two, each running every item's script. Here both happen under one lock, held as long as the
# bar runs, so a second start in the meantime gives up at once. That's a success: a bar is
# starting. lockf says so with 75, its "temporarily unavailable", which is turned into 0.
PATH="$PATH:/opt/homebrew/bin"
/usr/bin/lockf -s -t 0 "${TMPDIR:-/tmp}/omv-sketchybar.lock" \
  /bin/sh -c 'pgrep -x sketchybar >/dev/null || exec sketchybar'
status=$?
[ "$status" -eq 75 ] && exit 0
exit "$status"
