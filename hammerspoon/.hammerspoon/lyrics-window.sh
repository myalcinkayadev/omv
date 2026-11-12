#!/bin/sh
# Runs the lyrics window helper, reading Hammerspoon's commands on stdin. See lyrics-window.swift.
# The helper is built from lyrics-window.swift the first time, into an app bundle in the
# cache, so AeroSpace knows its window by the bundle's identifier.

PATH="$PATH:/usr/bin:/bin:/usr/sbin"

source_file=$(dirname "$0")/lyrics-window.swift
app=$HOME/.cache/omv/Lyrics.app
helper=$app/Contents/MacOS/lyrics-window

write_info() {
  cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.omv.lyrics</string>
  <key>CFBundleName</key><string>Lyrics</string>
  <key>CFBundleExecutable</key><string>lyrics-window</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
}

build_helper() {
  [ -x "$helper" ] && [ "$helper" -nt "$source_file" ] && return 0
  mkdir -p "$app/Contents/MacOS"
  write_info
  swiftc -O "$source_file" -o "$helper" >/dev/null 2>&1 || {
    echo "Couldn't build the lyrics window" >&2
    exit 1
  }
  codesign --force --sign - "$app" >/dev/null 2>&1
}

build_helper
# Run directly, not through open, so Hammerspoon's stdin reaches it.
exec "$helper"
