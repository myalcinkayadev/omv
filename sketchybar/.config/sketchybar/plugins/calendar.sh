#!/bin/sh
# Toggles the month popup under the clock. SketchyBar draws it on the active display.
# Today appears in brackets that reuse the spaces around it, so columns stay aligned.

line_count=8

if [ "$(sketchybar --query clock | jq -r '.popup.drawing')" = on ]; then
  sketchybar --set clock popup.drawing=off
  exit 0
fi

lines=$(cal -h | awk -v today="$(date '+%d')" '
  NF == 0 { next }
  {
    sub(/ +$/, "")
    row = " " sprintf("%-20s", $0) " "
    if (FNR > 2) {
      for (column = 0; column < 7; column++) {
        day = substr(row, 3 * column + 2, 2)
        if (day ~ /[0-9]/ && day + 0 == today + 0) {
          start = (today + 0 > 9) ? 3 * column + 1 : 3 * column + 2
          width = (today + 0 > 9) ? 2 : 1
          row = substr(row, 1, start - 1) "[" (today + 0) "]" substr(row, start + width + 2)
          break
        }
      }
    }
    print row
  }')

set --
number=1
while [ "$number" -le "$line_count" ]; do
  line=$(printf '%s\n' "$lines" | sed -n "${number}p")
  if [ -n "$line" ]; then
    set -- "$@" --set "cal.$number" "label=$line" drawing=on
  else
    set -- "$@" --set "cal.$number" drawing=off
  fi
  number=$((number + 1))
done

sketchybar "$@" --set clock popup.drawing=on
