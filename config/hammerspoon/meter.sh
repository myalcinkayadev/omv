#!/bin/sh
# Usage: meter.sh start <file> | meter.sh stop
# Starts or stops the mic level helper behind the Sound card's meter. See meter.swift.
# The helper is built from meter.swift the first time, into an app bundle in the cache,
# so macOS asks for the microphone by its own name.

PATH="$PATH:/usr/bin:/bin:/usr/sbin"

source_file=$(dirname "$0")/meter.swift
app=$HOME/.cache/omv/Meter.app
helper=$app/Contents/MacOS/meter

# The usage description is what macOS shows when it asks for the microphone.
write_info() {
  cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.omv.meter</string>
  <key>CFBundleName</key><string>omv meter</string>
  <key>CFBundleExecutable</key><string>meter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Shows the microphone's level in the Sound card while it is open.</string>
</dict>
</plist>
PLIST
}

build_helper() {
  [ -x "$helper" ] && [ "$helper" -nt "$source_file" ] && return 0
  mkdir -p "$app/Contents/MacOS"
  write_info
  swiftc -O "$source_file" -o "$helper" >/dev/null 2>&1 || {
    echo "Couldn't build the meter helper" >&2
    exit 1
  }
  # Signing the bundle seals its Info.plist, which macOS reads when it asks for access.
  codesign --force --sign - "$app" >/dev/null 2>&1
}

case ${1:-} in
  start)
    [ -n "${2:-}" ] || exit 2
    build_helper
    # -n starts a new one even while a stopped one is still exiting, -g keeps focus where
    # it is, -j starts it hidden. No -W: it runs until stopped.
    open -n -g -j "$app" --args "$2"
    ;;
  stop)
    # By its full path, so no other process called "meter" is touched.
    pkill -f "$helper"
    exit 0
    ;;
  *)
    echo "Usage: meter.sh start <file> | meter.sh stop" >&2
    exit 2
    ;;
esac
