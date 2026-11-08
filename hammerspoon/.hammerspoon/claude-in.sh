#!/bin/sh
# Usage: claude-in.sh <folder> [claude arguments...]
# Starts Claude Code in a folder, for the Agents card. It runs through your login shell,
# so claude is found on the PATH your shell sets up.

cd "$1" || exit 1
shift
exec "${SHELL:-/bin/zsh}" -lic 'claude "$@"' claude "$@"
