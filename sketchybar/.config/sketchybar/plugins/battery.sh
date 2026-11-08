#!/bin/sh
# Draws the battery icon, and opens the Battery card on a click.
# Nerd Font glyphs are written as octal UTF-8 bytes so they survive any editor.

if [ "${SENDER:-}" = mouse.clicked ]; then
  hs -c 'omvToggleBattery()'
  exit 0
fi

status=$(pmset -g batt)
battery_line=$(printf '%s\n' "$status" | sed -n '/InternalBattery/p' | head -n 1)

if [ -z "$battery_line" ]; then
  sketchybar --set "$NAME" icon='—' label='—'
  exit 0
fi

percent=$(printf '%s\n' "$battery_line" | sed -E 's/.*[[:space:]]([0-9]{1,3})%.*/\1/')

case $status in
  *"'AC Power'"*) glyph='\357\203\247' ;;
  *)
    if [ "$percent" -ge 90 ]; then
      glyph='\357\211\200'
    elif [ "$percent" -ge 60 ]; then
      glyph='\357\211\201'
    elif [ "$percent" -ge 35 ]; then
      glyph='\357\211\202'
    elif [ "$percent" -ge 10 ]; then
      glyph='\357\211\203'
    else
      glyph='\357\211\204'
    fi
    ;;
esac

sketchybar --set "$NAME" icon="$(printf "$glyph")" label="$percent%"
