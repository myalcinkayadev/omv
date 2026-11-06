#!/bin/sh
# Handles the icon, click-to-mute and scroll-to-change. Volume glyphs are octal UTF-8 bytes.

step=5

read_level() {
  osascript -e 'output volume of (get volume settings)'
}

scrolled_level() {
  current=$1
  case ${SCROLL_DELTA:-0} in
    0 | 0.0*) printf '%s' "$current" ;;
    -*) target=$((current - step)); [ "$target" -lt 0 ] && target=0; printf '%s' "$target" ;;
    *) target=$((current + step)); [ "$target" -gt 100 ] && target=100; printf '%s' "$target" ;;
  esac
}

case ${SENDER:-} in
  mouse.clicked)
    osascript -e 'set volume output muted not (output muted of (get volume settings))'
    level=$(read_level)
    ;;
  mouse.scrolled)
    level=$(read_level)
    case $level in
      '' | *[!0-9]*) ;;
      *)
        level=$(scrolled_level "$level")
        osascript -e "set volume output volume $level"
        ;;
    esac
    ;;
  volume_change) level=${INFO:-} ;;
  *) level=$(read_level) ;;
esac

muted=$(osascript -e 'output muted of (get volume settings)')

case $level in
  '' | *[!0-9]*) glyph='\357\200\250' ;;
  0) glyph='\357\200\246' ;;
  *)
    if [ "$level" -lt 50 ]; then
      glyph='\357\200\247'
    else
      glyph='\357\200\250'
    fi
    ;;
esac

[ "$muted" = true ] && glyph='\357\200\246'

sketchybar --set "$NAME" icon="$(printf "$glyph")"
