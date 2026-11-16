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

# Upright Material Design batteries, filled to the tens below the charge.
case $status in
  *"'AC Power'"*) glyph='\363\260\202\204' ;;
  *)
    case $((percent / 10)) in
      10) glyph='\363\260\201\271' ;;
      9) glyph='\363\260\202\202' ;;
      8) glyph='\363\260\202\201' ;;
      7) glyph='\363\260\202\200' ;;
      6) glyph='\363\260\201\277' ;;
      5) glyph='\363\260\201\276' ;;
      4) glyph='\363\260\201\275' ;;
      3) glyph='\363\260\201\274' ;;
      2) glyph='\363\260\201\273' ;;
      1) glyph='\363\260\201\272' ;;
      0) glyph='\363\260\202\216' ;;
    esac
    ;;
esac

sketchybar --set "$NAME" icon="$(printf "$glyph")" label="$percent%"
