#!/usr/bin/env bash
# Display profiles are now profiles: they hold workspaces and apps too, so their file is
# ~/.config/omv/profiles. Renames ~/.config/omv/displays when there's no profiles file yet;
# omv still reads displays while it's the only one.
set -euo pipefail

old=$HOME/.config/omv/displays
new=$HOME/.config/omv/profiles
[ -e "$old" ] || exit 0
[ -e "$new" ] && exit 0
mv "$old" "$new"
