#!/bin/sh

if ipconfig getifaddr en0 >/dev/null 2>&1; then
  glyph='\357\207\253'
else
  glyph='\363\260\226\252'
fi

sketchybar --set "$NAME" icon="$(printf "$glyph")"
