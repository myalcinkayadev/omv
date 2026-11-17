#!/bin/sh
# Asks for the password sudo needs while omv Setup installs. A window app has no terminal for
# sudo to ask in; with SUDO_ASKPASS set, Homebrew runs sudo -A, which runs this. Prints what
# was typed; fails on Cancel, which stops that sudo.
# Usage: askpass.sh <prompt>

osascript \
  -e 'display dialog "omv Setup needs your password for Homebrew." default answer "" with hidden answer with title "omv Setup" with icon caution' \
  -e 'text returned of result'
