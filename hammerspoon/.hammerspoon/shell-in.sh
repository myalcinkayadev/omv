#!/bin/sh
# Usage: shell-in.sh <folder>
# Opens your login shell in a folder, for the dev layout's terminal window.

cd "$1" || exit 1
exec "${SHELL:-/bin/zsh}" -l
