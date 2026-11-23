#!/bin/sh
# Prints "N<tab>text" for each workspace ~/.config/omv/workspaces names, the text as its bar
# line formats it, such as "1 Code". A workspace without a name shows its number, so isn't
# printed; neither is anything without the file or luajit.

file=$HOME/.config/omv/workspaces
[ -r "$file" ] || exit 0
hammerspoon=$(dirname "$(readlink -f "$0")")/../../../../hammerspoon
cd "$hammerspoon" 2>/dev/null && luajit workspaces.lua texts "$file" 2>/dev/null
exit 0
