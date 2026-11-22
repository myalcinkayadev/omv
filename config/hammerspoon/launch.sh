#!/bin/sh
# Usage: launch.sh <workspace> <command...>
# Switches workspace first because AeroSpace routes new windows without following them. An
# empty workspace stays on the one you're on, for an app no workspace keeps.
# The command still runs if the switch fails, for example after AeroSpace is removed.

PATH="$PATH:/opt/homebrew/bin"

workspace=$1
shift

[ -n "$workspace" ] && aerospace workspace "$workspace"
exec "$@"
