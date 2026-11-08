#!/bin/sh
# Usage: agenda.sh
# Prints today's Calendar.app events, one per line: start, end, all-day (1 or 0), title and
# video call links, split by tabs, or "denied" when Calendar access was refused. See agenda.swift.
# The helper is built from agenda.swift the first time, into an app bundle in the cache.

PATH="$PATH:/usr/bin:/bin:/usr/sbin"

source_file=$(dirname "$0")/agenda.swift
app=$HOME/.cache/omv/Agenda.app
helper=$app/Contents/MacOS/agenda
output=$HOME/.cache/omv/agenda

# The usage descriptions are what macOS shows when it asks for Calendar access.
write_info() {
  cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.omv.agenda</string>
  <key>CFBundleName</key><string>omv agenda</string>
  <key>CFBundleExecutable</key><string>agenda</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Shows today's events in the calendar card and the next meeting in the bar.</string>
  <key>NSCalendarsUsageDescription</key><string>Shows today's events in the calendar card and the next meeting in the bar.</string>
</dict>
</plist>
PLIST
}

build_helper() {
  [ -x "$helper" ] && [ "$helper" -nt "$source_file" ] && return 0
  mkdir -p "$app/Contents/MacOS"
  write_info
  swiftc -O "$source_file" -o "$helper" >/dev/null 2>&1 || {
    echo "Couldn't build the agenda helper" >&2
    exit 1
  }
  # Signing the bundle seals its Info.plist, which macOS reads when it asks for access.
  codesign --force --sign - "$app" >/dev/null 2>&1
}

build_helper
rm -f "$output"
# -W waits for it to finish, -g keeps focus where it is, -j starts it hidden.
open -W -g -j "$app" --args "$output" || exit 1
[ -f "$output" ] || {
  echo "The agenda helper wrote nothing" >&2
  exit 1
}
cat "$output"
