#!/bin/sh
# Usage: brew-upgrade.sh
# Runs `brew upgrade` for the bar's outdated-packages item, in the Ghostty window its click
# opens. Unlike the bar's count, this one updates Homebrew first, as `brew upgrade` does.

PATH="$PATH:/opt/homebrew/bin"

# The window was started by typing a command into it; clearing the screen and scrollback
# hides that line.
printf '\033[H\033[2J\033[3J'
brew upgrade
# Counted again now, not once the window closes, since closing it with Cmd+W skips the rest.
sketchybar --trigger brew_outdated_change
# Ghostty's window closes when its command exits, so brew's summary stays until Enter.
printf '\nPress Enter to close'
read -r _
