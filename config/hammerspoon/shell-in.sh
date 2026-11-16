#!/bin/sh
# Usage: shell-in.sh <folder>
# Opens your login shell in a folder, for the dev layout's terminal window.

cd "$1" || exit 1
# The window was started by typing a command into it; clearing the screen and scrollback
# hides that line, so the shell opens clean.
printf '\033[H\033[2J\033[3J'
exec "${SHELL:-/bin/zsh}" -l
