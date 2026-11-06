#!/bin/sh

if [ "${SENDER:-}" = mouse.exited.global ]; then
  sketchybar --set clock popup.drawing=off
  exit 0
fi

sketchybar --set clock label="$(date '+%A %H:%M')"
