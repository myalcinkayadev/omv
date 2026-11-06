#!/bin/sh
# Styles all six workspace items with one sketchybar call. Workspaces are global,
# so every bar shows the same items: the focused one, the one visible on the other
# monitor, and the rest.

focused=${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}

case $focused in
  1 | 2 | 3 | 4 | 5 | 6) ;;
  *) exit 0 ;;
esac

visible=$(aerospace list-workspaces --monitor all --visible 2>/dev/null)

set --
for number in 1 2 3 4 5 6; do
  if [ "$number" = "$focused" ]; then
    style='background.color=0xffffffff icon.color=0xff000000'
  elif printf '%s\n' "$visible" | grep -qx "$number"; then
    style='background.color=0xff3a3a3a icon.color=0xffffffff'
  else
    style='background.color=0x00000000 icon.color=0xff7a7a7a'
  fi
  # Word splitting is intended: style holds only space-separated properties.
  # shellcheck disable=SC2086
  set -- "$@" --set "space.$number" $style
done

sketchybar "$@"
