#!/bin/sh
# Usage: launch.sh <workspace> <command...>
# Switches workspace first because AeroSpace routes new windows without following them.
# The command still runs if the switch fails, for example after AeroSpace is removed.

PATH="$PATH:/opt/homebrew/bin"

workspace=$1
shift

aerospace workspace "$workspace"
exec "$@"
