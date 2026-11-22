#!/bin/sh
# Prints the workspaces the bar shows, in number order: the ones AeroSpace keeps alive, which
# omv builds from ~/.config/omv/workspaces. Without an answer from AeroSpace, today's seven.

numbers=$(aerospace list-workspaces --all 2>/dev/null | grep -xE '[1-9]' | sort -n | tr '\n' ' ')
[ -n "$numbers" ] || numbers='1 2 3 4 5 6 7 '
printf '%s\n' "${numbers% }"
