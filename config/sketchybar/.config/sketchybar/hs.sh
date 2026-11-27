#!/bin/sh
# Runs the Lua in $1 in Hammerspoon for the bar and its clicks, giving up after OMV_HS_SECONDS,
# 3 unless set: hs -c can wait forever, even with -t, when a reload drops the call, and calls
# that never end would pile up. perl's alarm outlives exec, and macOS has no timeout command.
exec perl -e 'alarm shift; exec @ARGV' "${OMV_HS_SECONDS:-3}" hs -t 2 -c "$1"
