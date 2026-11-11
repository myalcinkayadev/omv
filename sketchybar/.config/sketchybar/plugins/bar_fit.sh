#!/bin/sh
# Keeps the right side of the bar clear of the notch. Run after an item there changes.
# It shows everything, measures, then gives way in this order until it fits:
#   1. Claude's 5-hour limit (its logo stays)
#   2. the meeting's time (its icon stays)
#   3. the weather's temperature (its icon stays)
#   4. the Claude logo
# Keep-awake, paused clipboard history, the waiting Claude, the pull request count, the reminder and the status icons never give way.

PATH="$PATH:/opt/homebrew/bin"

# SketchyBar's default notch width, a little wider than the notch itself.
notch_width=200
claude_logo_width=27
meeting_icon_width=26
weather_icon_width=26

sketchybar --set claude_usage icon.drawing=on label.drawing=on --set meeting label.drawing=on --set weather label.drawing=on

# Prints "<display> <left> <width>" for an item drawn on each display, nothing if hidden.
rects() {
  sketchybar --query "$1" | jq -r '
    select(.geometry.drawing == "on")
    | .bounding_rects | to_entries[]
    | "\(.key | ltrimstr("display-")) \(.value.origin[0]) \(.value.size[0])"'
}

# Each display needs room up to its notch's right edge, so the worst one decides.
# An item's left edge is counted from the main display's corner, not its own display's, so
# the display's own left edge is taken off: on a display placed to the left it is negative.
need=0
for display in $(sketchybar --query displays | jq -r '.[]."arrangement-id"'); do
  # shellcheck disable=SC2046
  set -- $(sketchybar --query displays | jq -r --argjson id "$display" '.[] | select(."arrangement-id" == $id) | "\(.frame.x) \(.frame.w)"')
  display_left=$1
  width=$2
  leftmost=$(for name in clock battery volume bluetooth wifi ethernet weather claude_usage github_prs claude_waiting keep_awake clipboard_paused reminder meeting; do rects "$name"; done |
    awk -v d="$display" '$1 == d { if (min == "" || $2 < min) min = $2 } END { print min }')
  [ -n "$leftmost" ] || continue
  short=$(awk -v w="$width" -v n="$notch_width" -v l="$leftmost" -v x="$display_left" 'BEGIN { printf "%d", w / 2 + n / 2 - (l - x) }')
  [ "$short" -gt "$need" ] && need=$short
done
[ "$need" -gt 0 ] || exit 0

width_of() {
  rects "$1" | awk '{ print int($3); exit }'
}

claude=$(width_of claude_usage)
if [ -n "$claude" ] && [ "$need" -gt 0 ]; then
  sketchybar --set claude_usage label.drawing=off
  need=$((need - (claude - claude_logo_width)))
fi

meeting=$(width_of meeting)
if [ -n "$meeting" ] && [ "$need" -gt 0 ]; then
  sketchybar --set meeting label.drawing=off
  need=$((need - (meeting - meeting_icon_width)))
fi

weather=$(width_of weather)
if [ -n "$weather" ] && [ "$need" -gt 0 ]; then
  sketchybar --set weather label.drawing=off
  need=$((need - (weather - weather_icon_width)))
fi

if [ -n "$claude" ] && [ "$need" -gt 0 ]; then
  sketchybar --set claude_usage icon.drawing=off
fi
