#!/bin/sh
# Called from the status line. Saves only the Claude usage percentages and reset times
# for the bar, and notifies it when they change. Always exits 0.

PATH="$PATH:/opt/homebrew/bin"
state_file="$HOME/.local/state/omv/claude-usage"

usage=$(jq -r '
  .rate_limits as $limits
  | select($limits.five_hour.used_percentage != null and $limits.seven_day.used_percentage != null)
  | "\($limits.five_hour.used_percentage) \($limits.five_hour.resets_at) \($limits.seven_day.used_percentage) \($limits.seven_day.resets_at)"
' 2>/dev/null)

[ -n "$usage" ] || exit 0
[ "$usage" = "$(cat "$state_file" 2>/dev/null)" ] && exit 0

mkdir -p "$(dirname "$state_file")" 2>/dev/null
printf '%s\n' "$usage" > "$state_file" 2>/dev/null
sketchybar --trigger claude_usage_change >/dev/null 2>&1
exit 0
