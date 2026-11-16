#!/bin/sh
# Usage: share.sh
# Shares with AirDrop: the files selected in Finder, else a file copied to the clipboard,
# else an image copied to the clipboard, saved as a PNG first. Opens macOS's AirDrop sheet
# through a small Swift helper, built from share.swift the first time and cached.
# Exits non-zero when there's nothing to share or the share fails.

PATH="$PATH:/usr/bin:/bin"

source_file=$(dirname "$0")/share.swift
helper=$HOME/.cache/omv/share

build_helper() {
  [ -x "$helper" ] && [ "$helper" -nt "$source_file" ] && return 0
  mkdir -p "$(dirname "$helper")"
  swiftc -O "$source_file" -o "$helper" >/dev/null 2>&1 || {
    echo "Couldn't build the share helper" >&2
    exit 1
  }
}

finder_selection() {
  osascript -e 'tell application "Finder" to set picked to selection as alias list' \
    -e 'set paths to ""' \
    -e 'repeat with item_ in picked' \
    -e 'set paths to paths & POSIX path of item_ & linefeed' \
    -e 'end repeat' \
    -e 'return paths' 2>/dev/null
}

copied_file() {
  osascript -e 'POSIX path of (the clipboard as «class furl»)' 2>/dev/null
}

# Writes the copied image to a PNG and prints its path; nothing when no image is copied.
copied_image() {
  image=$(mktemp -t omv-share).png
  osascript -e "set target to open for access POSIX file \"$image\" with write permission" \
    -e 'set eof of target to 0' \
    -e 'write (the clipboard as «class PNGf») to target' \
    -e 'close access target' >/dev/null 2>&1 || { rm -f "$image"; return 1; }
  printf '%s\n' "$image"
}

files=$(finder_selection)
[ -n "$files" ] || files=$(copied_file)
[ -n "$files" ] || files=$(copied_image)
if [ -z "$files" ]; then
  echo "Nothing to share: select files in Finder, or copy a file or image" >&2
  exit 1
fi

build_helper
# One path a line, so names with spaces stay whole.
set --
while IFS= read -r path; do
  [ -n "$path" ] && set -- "$@" "$path"
done <<LIST
$files
LIST
exec "$helper" airdrop "$@"
