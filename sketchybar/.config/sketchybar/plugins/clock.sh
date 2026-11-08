#!/bin/sh
# The date and time as the macOS menu bar shows them, such as "Sun Nov 8 12:09".

sketchybar --set clock label="$(date '+%a %b %-d %H:%M')"
