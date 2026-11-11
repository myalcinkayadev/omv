#!/bin/sh
# Styles all six workspace items with one sketchybar call. Workspaces are global,
# so every bar shows the same items: the focused one, the one visible on the other
# monitor, and the rest.

# Vantablack's colours, unless a theme was chosen in the system menu.
WHITE=0xffffffff MUTED=0xff7a7a7a BLACK=0xff000000 GRAY=0xff3a3a3a
# shellcheck disable=SC1091
[ -r "$HOME/.local/state/omv/theme/colors.sh" ] && . "$HOME/.local/state/omv/theme/colors.sh"

focused=${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}

case $focused in
  1 | 2 | 3 | 4 | 5 | 6) ;;
  *) exit 0 ;;
esac

visible=$(aerospace list-workspaces --monitor all --visible 2>/dev/null)

set --
for number in 1 2 3 4 5 6; do
  if [ "$number" = "$focused" ]; then
    style="background.color=$WHITE icon.color=$BLACK"
  elif printf '%s\n' "$visible" | grep -qx "$number"; then
    style="background.color=$GRAY icon.color=$WHITE"
  else
    style="background.color=0x00000000 icon.color=$MUTED"
  fi
  # Word splitting is intended: style holds only space-separated properties.
  # shellcheck disable=SC2086
  set -- "$@" --set "space.$number" $style
done

sketchybar "$@"
