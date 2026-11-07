# Shared test harness. Source this from a *_test.sh file.
#
# Every case gets a fresh sandbox: a temporary HOME plus stubs for each command
# that could touch the real system. Scripts under test run with a clean
# environment and a PATH that resolves those commands to the stubs first, so a
# test can never quit a real app, write a real default or change real symlinks.

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_DIR
readonly REAL_STOW=$(command -v stow)
readonly SYSTEM_COMMANDS=(aerospace brew defaults killall open osascript pgrep pkill sketchybar stow)

passed=0
failed=0

stub() {
  local name=$1 exit_code=${2:-0}
  cat > "$STUB_DIR/$name" <<EOF
#!/bin/sh
echo "$name \$*" >> "$CALL_LOG"
exit $exit_code
EOF
  chmod +x "$STUB_DIR/$name"
}

remove_stub() {
  rm -f "$STUB_DIR/$1"
}

use_real_stow() {
  ln -sf "$REAL_STOW" "$STUB_DIR/stow"
}

new_sandbox() {
  SANDBOX=$(mktemp -d)
  STUB_DIR=$SANDBOX/bin
  CALL_LOG=$SANDBOX/calls.log
  HOME_DIR=$SANDBOX/home
  mkdir -p "$STUB_DIR" "$HOME_DIR"
  : > "$CALL_LOG"
  local name
  for name in "${SYSTEM_COMMANDS[@]}"; do
    stub "$name"
  done
}

run_in_sandbox() {
  env -i HOME="$HOME_DIR" PATH="$STUB_DIR:/usr/bin:/bin" CALL_LOG="$CALL_LOG" "$@"
}

# Assertions print the reason and return non-zero, which fails the case.
fail() {
  echo "    $1"
  return 1
}

assert_called() {
  grep -qE -e "$1" "$CALL_LOG" || fail "expected a call matching: $1"$'\n'"$(cat "$CALL_LOG")"
}

assert_not_called() {
  if grep -qE -e "$1" "$CALL_LOG"; then
    fail "unexpected call matching: $1"
  fi
}

assert_exit_zero() {
  "$@" >/dev/null 2>&1 || fail "expected success: $*"
}

assert_exit_nonzero() {
  if "$@" >/dev/null 2>&1; then
    fail "expected failure: $*"
  fi
}

# Runs one case in a subshell so a failure cannot leak state into the next case.
# The subshell must not sit inside an if: bash ignores set -e there, so only the
# last assertion would count.
run_case() {
  local name=$1 case_function=$2 status
  (set -e; new_sandbox; "$case_function")
  status=$?
  if [ "$status" -eq 0 ]; then
    passed=$((passed + 1))
    echo "ok   - $name"
  else
    failed=$((failed + 1))
    echo "FAIL - $name"
  fi
}

finish() {
  echo "$passed passed, $failed failed"
  [ "$failed" -eq 0 ]
}
