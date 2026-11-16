#!/bin/sh
# Counts the open pull requests that ask for your review, and opens the pull request card
# on a click. Hidden when none wait, and when gh is missing, logged out or offline, so a
# stale count never shows. GH can point the tests at a stub.

gh=${GH:-/opt/homebrew/bin/gh}

if [ "${SENDER:-}" = mouse.clicked ]; then
  hs -c 'omvTogglePrs()'
  exit 0
fi

hide() {
  sketchybar --set "$NAME" drawing=off
  sketchybar --trigger bar_fit
  exit 0
}

[ -x "$gh" ] || hide
count=$("$gh" search prs --review-requested=@me --state=open --json number --jq length 2>/dev/null) || hide

case $count in
  '' | *[!0-9]* | 0) hide ;;
esac

sketchybar --set "$NAME" drawing=on "label=$count"
# The label's width changes, so the right side may need to give way before the notch.
sketchybar --trigger bar_fit
