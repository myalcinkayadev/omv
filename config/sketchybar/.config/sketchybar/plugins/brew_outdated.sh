#!/bin/sh
# Counts the Homebrew packages `brew outdated` lists, every 6 hours and on wake, and opens
# `brew upgrade` in a Ghostty window on a click. Hidden at 0 and when brew is missing; a count
# that fails twice leaves the item as it was. BREW and BREW_RETRY_SECONDS are for the tests.
# The count never runs `brew update` and never reaches the network, so it's only as fresh as
# your last `brew update` or `brew upgrade`.

brew=${BREW:-/opt/homebrew/bin/brew}
state_dir="$HOME/.local/state/omv"
# When the last count finished, in seconds since 1970.
stamp="$state_dir/brew-outdated"
# A wake within this long of the last count keeps that count: each one takes brew a second
# or two of CPU, and the Mac may wake many times an hour.
fresh_seconds=3600

if [ "${SENDER:-}" = mouse.clicked ]; then
  # The upgrade changes the count, so the next wake counts again even if the window was
  # closed before brew finished.
  rm -f "$stamp"
  hs -c 'omvBrewUpgrade()'
  exit 0
fi

hide() {
  sketchybar --set "$NAME" drawing=off
  sketchybar --trigger bar_fit
  exit 0
}

if [ "${SENDER:-}" = system_woke ] && [ -r "$stamp" ]; then
  read -r last < "$stamp"
  case $last in
    '' | *[!0-9]*) ;;
    *) [ $(($(date +%s) - last)) -lt "$fresh_seconds" ] && exit 0 ;;
  esac
fi

[ -x "$brew" ] || hide

# Auto-update would run `brew update` first, which fetches from GitHub; the hints and
# analytics are of no use to a script.
# Started from SketchyBar, brew crashes every time ("undefined method 'exitstatus' for nil",
# when it waits on a command of its own), while the same call through perl's exec works every
# time; why that helps isn't known: not the inherited files, nor SIGCHLD as perl sees it.
count_outdated() {
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_ANALYTICS=1 \
    perl -e 'exec @ARGV' "$brew" outdated --quiet 2>/dev/null
}

# A count that fails, such as one asked while the upgrade the click opened is still finishing,
# is asked once more a little later. A second failure leaves the item as it was: hiding it
# would drop a count that was right.
outdated=$(count_outdated) || {
  sleep "${BREW_RETRY_SECONDS:-30}"
  outdated=$(count_outdated)
} || exit 0

mkdir -p "$state_dir" 2>/dev/null
date +%s > "$stamp"

count=$(printf '%s\n' "$outdated" | awk 'NF { n++ } END { print n + 0 }')
[ "$count" -gt 0 ] || hide

sketchybar --set "$NAME" drawing=on "label=$count"
# The label's width changes, so the right side may need to give way before the notch.
sketchybar --trigger bar_fit
