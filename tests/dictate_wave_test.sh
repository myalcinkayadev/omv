#!/usr/bin/env bash
# Builds the dictation helper and runs its own checks of the wave it draws: the gain, the
# curves and the commands Hammerspoon sends it. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
/usr/bin/swiftc -Onone "$REPO_DIR/config/hammerspoon/dictate.swift" -o "$build_dir/dictate" 2>"$build_dir/errors" || {
  cat "$build_dir/errors" >&2
  echo "FAIL - should build the dictation helper"
  exit 1
}
"$build_dir/dictate" selftest || exit 1

# Hammerspoon writes to the helper's stdin, and writing to a pipe nobody reads kills the
# writer, so after its last line, here a problem, the helper must keep reading until
# Hammerspoon closes its input.
mkfifo "$build_dir/input"
"$build_dir/dictate" listen xx-YY dictation < "$build_dir/input" > "$build_dir/output" 2>/dev/null &
helper=$!
exec 3> "$build_dir/input"
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q '^problem' "$build_dir/output" && break; sleep 0.5; done
sleep 0.5
if grep -q '^problem' "$build_dir/output" && kill -0 "$helper" 2>/dev/null; then
  echo "ok   - should keep reading its input after its last line"
else
  echo "FAIL - should keep reading its input after its last line"
fi
exec 3>&-
for _ in 1 2 3 4 5 6; do kill -0 "$helper" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$helper" 2>/dev/null; then
  kill "$helper"
  echo "FAIL - should end once its input closes"
else
  echo "ok   - should end once its input closes"
fi
