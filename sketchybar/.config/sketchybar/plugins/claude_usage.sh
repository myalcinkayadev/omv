#!/bin/sh
# Shows Claude's 5-hour and 7-day usage. A click shows reset times for 10 seconds.
# The numbers only update while Claude Code runs, so a window past its reset shows 0%.

state_file="$HOME/.local/state/omv/claude-usage"
resets_view="$state_file-resets-view"

if [ ! -r "$state_file" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

# Reset times are the widest label, so they switch back to percentages after 10 seconds,
# keeping the right side of the bar clear of the notch. The file holds a token, so a
# timer from an earlier click never cuts a later view short.
show_resets_briefly() {
  token=$$-$(date +%s)
  printf '%s' "$token" > "$resets_view"
  (
    sleep 10
    [ "$(cat "$resets_view" 2>/dev/null)" = "$token" ] || exit 0
    rm -f "$resets_view"
    sketchybar --trigger claude_usage_change
  ) >/dev/null 2>&1 &
}

if [ "${SENDER:-}" = mouse.clicked ]; then
  if [ -e "$resets_view" ]; then
    rm -f "$resets_view"
  else
    show_resets_briefly
  fi
fi

read -r five_used five_reset seven_used seven_reset < "$state_file"

percent() {
  if [ "${2%.*}" -le "$now" ]; then
    echo 0
  else
    printf '%.0f' "$1"
  fi
}

reset_time() {
  if [ "${1%.*}" -le "$now" ]; then
    echo -
  else
    date -r "${1%.*}" "$2"
  fi
}

now=$(date +%s)
five=$(percent "$five_used" "$five_reset")
seven=$(percent "$seven_used" "$seven_reset")

highest=$five
[ "$seven" -gt "$highest" ] && highest=$seven

if [ -e "$resets_view" ]; then
  label="5h $(reset_time "$five_reset" '+%H:%M')  7d $(reset_time "$seven_reset" '+%a %H:%M')"
else
  label="5h $five%  7d $seven%"
fi

if [ "$highest" -ge 90 ]; then
  style='label.color=0xff000000 background.drawing=on'
elif [ "$highest" -ge 70 ]; then
  style='label.color=0xffffffff background.drawing=off'
else
  style='label.color=0xff7a7a7a background.drawing=off'
fi

# Word splitting is intended: style holds only space-separated properties.
# shellcheck disable=SC2086
sketchybar --set "$NAME" drawing=on "label=$label" $style
