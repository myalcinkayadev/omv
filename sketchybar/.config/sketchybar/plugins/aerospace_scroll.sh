#!/bin/sh
# Scrolling over a workspace number moves one workspace, wrapping around. It computes the
# number itself because workspaces are pinned to monitors, and this crosses between them.
# A trackpad sends many events per swipe, so moves are limited to one per 300ms.

workspace_count=7
minimum_gap_ms=300
stamp_file="$HOME/.local/state/omv/scroll-stamp"

case ${SCROLL_DELTA:-0} in
  0 | 0.0* | -0 | -0.0*) exit 0 ;;
  -*) step=-1 ;;
  *) step=1 ;;
esac

now=$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000')
last=$(cat "$stamp_file" 2>/dev/null || echo 0)
[ $((now - last)) -lt "$minimum_gap_ms" ] && exit 0

focused=$(aerospace list-workspaces --focused 2>/dev/null)
case $focused in
  1 | 2 | 3 | 4 | 5 | 6 | 7) ;;
  *) exit 0 ;;
esac

mkdir -p "$(dirname "$stamp_file")"
echo "$now" > "$stamp_file"
aerospace workspace $(((focused - 1 + step + workspace_count) % workspace_count + 1))
