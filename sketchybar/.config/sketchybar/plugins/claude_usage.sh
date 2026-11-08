#!/bin/sh
# Shows Claude's 5-hour limit next to its logo, and opens the Agents card on a click; the
# 7-day limit is in the card. Gray under 70%, white from 70%, and a white pill from 90%.
# The number only updates while Claude Code runs, so a session past its reset shows 0%.

state_file="$HOME/.local/state/omv/claude-usage"

if [ "${SENDER:-}" = mouse.clicked ]; then
  hs -c 'omvToggleAgents()'
  exit 0
fi

if [ ! -r "$state_file" ]; then
  sketchybar --set "$NAME" drawing=off
  sketchybar --trigger bar_fit
  exit 0
fi

read -r five_used five_reset _ < "$state_file"

if [ "${five_reset%.*}" -le "$(date +%s)" ]; then
  five=0
else
  five=$(printf '%.0f' "$five_used")
fi

if [ "$five" -ge 90 ]; then
  style='label.color=0xff000000 background.drawing=on'
elif [ "$five" -ge 70 ]; then
  style='label.color=0xffffffff background.drawing=off'
else
  style='label.color=0xff7a7a7a background.drawing=off'
fi

# Word splitting is intended: style holds only space-separated properties.
# shellcheck disable=SC2086
sketchybar --set "$NAME" drawing=on "label=5h $five%" $style
# The label's width changes, so the right side may need to give way before the notch.
sketchybar --trigger bar_fit
