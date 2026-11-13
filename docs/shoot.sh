#!/bin/sh
# Retakes the README's card screenshots, from the sample data in docs/shots.lua, so no real
# network, place, event or path ends up in them.
# Usage: docs/shoot.sh [name...]   e.g. docs/shoot.sh disk wifi   (no names: every card)
#
# Needs Hammerspoon running with omv's config and the built-in Retina screen, where each
# card opens so it comes out at 2x. Leave the Mac alone until it's done: cards take focus.
# The screen must be awake and unlocked; a capture that fails is listed as FAILED.
#
# workspace-1.png, tabbed.png and bar.png show real windows, so they're taken by hand:
#   bar.png          screencapture of the bar's 34pt on the built-in screen
#   workspace-1.png  workspace 1 with btop and Neovim on the README
#   tabbed.png       three windows tiled, then tabbed with Option+A, side by side

docs=$(cd "$(dirname "$0")" && pwd)
done_file=$(mktemp)
rm -f "$done_file"

only=nil
if [ "$#" -gt 0 ]; then
  only="{"
  for name in "$@"; do only="$only[\"${name%.png}.png\"]=true,"; done
  only="$only}"
fi

# Deferred with a timer, so hs -c returns before the first card takes focus.
hs -c "hs.timer.doAfter(0.1, function() dofile('$docs/shoot.lua')('$docs', $only, '$done_file') end)" >/dev/null || exit 1

waited=0
while [ ! -f "$done_file" ]; do
  sleep 1
  waited=$((waited + 1))
  if [ "$waited" -ge 180 ]; then
    echo "Gave up after 3 minutes; is Hammerspoon running omv's config?" >&2
    exit 1
  fi
done

cat "$done_file"
grep -q '^FAILED' "$done_file" && status=1 || status=0
rm -f "$done_file"
exit "$status"
