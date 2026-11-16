# The setup assistant, omv Setup: a small app that walks through the macOS permissions omv
# needs. Built on this Mac from install/setup/*.swift, so macOS opens it without asking for a
# signed developer, the way omv's other Swift helpers are. Sourced, not run, after REPO_DIR.
# shellcheck disable=SC2034
readonly SETUP_APP=$HOME/Applications/omv\ Setup.app
readonly SETUP_BINARY=$SETUP_APP/Contents/MacOS/omv-setup

setup_info() {
  cat > "$SETUP_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.omv.setup</string>
  <key>CFBundleName</key><string>omv Setup</string>
  <key>CFBundleExecutable</key><string>omv-setup</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
}

# Builds the app when it's missing or older than its sources. Returns non-zero, saying how to
# fix it, when swiftc can't build it.
build_setup_app() {
  local source newest=0
  for source in "$REPO_DIR"/install/setup/*.swift; do
    if [ ! "$SETUP_BINARY" -nt "$source" ]; then newest=1; fi
  done
  [ -x "$SETUP_BINARY" ] && [ "$newest" -eq 0 ] && return 0
  mkdir -p "$SETUP_APP/Contents/MacOS" || return 1
  setup_info
  if ! swiftc -O "$REPO_DIR"/install/setup/*.swift -o "$SETUP_BINARY" >/dev/null 2>&1; then
    echo "omv: couldn't build omv Setup; Xcode's Command Line Tools are needed: xcode-select --install" >&2
    return 1
  fi
  codesign --force --sign - "$SETUP_APP" >/dev/null 2>&1 || true
}

open_setup_app() {
  build_setup_app || return 1
  open "$SETUP_APP"
}
