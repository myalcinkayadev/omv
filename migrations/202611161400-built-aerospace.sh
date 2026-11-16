#!/usr/bin/env bash
# omv now builds ~/.config/aerospace/aerospace.toml instead of linking the folder, so the
# user's settings can live in ~/.config/omv/aerospace.toml. This removes omv's folder link so
# the built file can go there. A real folder, or a link elsewhere, stays. Safe on a fresh
# setup and safe to run twice.

set -euo pipefail

CLONE=$(cd "$(dirname "$0")/.." && pwd -P)
readonly CLONE
readonly LINK=$HOME/.config/aerospace

[ -L "$LINK" ] || exit 0
[ "$LINK" -ef "$CLONE/config/aerospace/.config/aerospace" ] || exit 0
rm "$LINK"
echo "removed .config/aerospace"
