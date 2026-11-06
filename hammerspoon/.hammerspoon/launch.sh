#!/bin/sh
# Usage: launch.sh <workspace> <open arguments...>
# Switches workspace first because AeroSpace routes new windows without following them.
# The app still opens if the switch fails, for example after AeroSpace is removed.

PATH="$PATH:/opt/homebrew/bin"

workspace=$1
shift

aerospace workspace "$workspace"
exec open "$@"
