#!/bin/sh
# Prints the workspaces the bar shows, in number order: those omv builds into aerospace.toml
# from ~/.config/omv/workspaces. AeroSpace also keeps a workspace a screen shows, such as one
# removed from the file on a screen no workspace is pinned to; that one isn't drawn. Without
# the built file, the ones AeroSpace has; without an answer from AeroSpace, today's seven.

built=$HOME/.config/aerospace/aerospace.toml
numbers=$(grep -m 1 '^persistent-workspaces' "$built" 2>/dev/null | grep -oE "'[1-9]'" | tr -d "'" | sort -n | tr '\n' ' ')
[ -n "$numbers" ] || numbers=$(aerospace list-workspaces --all 2>/dev/null | grep -xE '[1-9]' | sort -n | tr '\n' ' ')
[ -n "$numbers" ] || numbers='1 2 3 4 5 6 7 '
printf '%s\n' "${numbers% }"
