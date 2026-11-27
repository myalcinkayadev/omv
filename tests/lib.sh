# Shared test harness. Source this from a *_test.sh file.
#
# Every case gets a fresh sandbox: a temporary HOME plus stubs for each command
# that could touch the real system. Scripts under test run with a clean
# environment and a PATH that resolves those commands to the stubs first, so a
# test can never quit a real app, write a real default or change real symlinks.

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_DIR
readonly REAL_STOW=$(command -v stow)
readonly REAL_LUAJIT=$(command -v luajit)
readonly SYSTEM_COMMANDS=(aerospace brew defaults killall open osascript pgrep pkill sketchybar stow)

passed=0
failed=0

# macOS checks each new executable the first time it runs, which takes about 0.2s. A fresh
# script per stub in every case added minutes to a test file, so every stub is a link to one
# script, written and run once per test file. It logs its name, from the link it was run
# through, and exits with the code in exits/<name> beside the call log, or 0; run_in_sandbox
# passes no other variable. Read-only, so a test that writes a stub of its own without
# removing the link first fails instead of changing every stub.
readonly SHARED_STUB_DIR=$(mktemp -d)
readonly SHARED_STUB=$SHARED_STUB_DIR/stub
cat > "$SHARED_STUB" <<'EOF'
#!/bin/sh
name=${0##*/}
echo "$name $*" >> "$CALL_LOG"
code=0
[ -f "${CALL_LOG%/*}/exits/$name" ] && read -r code < "${CALL_LOG%/*}/exits/$name"
exit "$code"
EOF
chmod 555 "$SHARED_STUB"
CALL_LOG=/dev/null "$SHARED_STUB"

# The system commands a case reaches with no stub of its own, such as one its stub file
# isn't executable for: the shell then looks further along PATH, and a real pkill there once
# stopped the running bar. These stand between the stubs and /usr/bin, and only say so.
readonly GUARD_DIR=$SHARED_STUB_DIR/guard
mkdir "$GUARD_DIR"
cat > "$GUARD_DIR/guard" <<'EOF'
#!/bin/sh
echo "${0##*/}: blocked, a test reached the real command" >&2
echo "blocked ${0##*/} $*" >> "$CALL_LOG"
exit 127
EOF
chmod 555 "$GUARD_DIR/guard"
# Only those PATH would find there: one that isn't, such as brew, stays missing when removed.
for name in "${SYSTEM_COMMANDS[@]}"; do
  [ -x "/usr/bin/$name" ] || [ -x "/bin/$name" ] && ln -s "$GUARD_DIR/guard" "$GUARD_DIR/$name"
done
CALL_LOG=/dev/null "$GUARD_DIR/guard" 2>/dev/null
trap 'rm -rf "$SHARED_STUB_DIR"' EXIT

stub() {
  local name=$1 exit_code=${2:-0}
  # A link, such as the real luajit's, is removed first, so the stub never writes through it.
  rm -f "$STUB_DIR/$name" "$SANDBOX/exits/$name"
  ln -s "$SHARED_STUB" "$STUB_DIR/$name"
  [ "$exit_code" = 0 ] || echo "$exit_code" > "$SANDBOX/exits/$name"
}

remove_stub() {
  rm -f "$STUB_DIR/$1" "$SANDBOX/exits/$1"
}

# Makes name's stub an empty executable file of the case's own, for the case to write its
# script into; writing through the link would reach the shared stub.
own_stub() {
  remove_stub "$1"
  : > "$STUB_DIR/$1"
  chmod +x "$STUB_DIR/$1"
}

use_real_stow() {
  ln -sf "$REAL_STOW" "$STUB_DIR/stow"
}

new_sandbox() {
  SANDBOX=$(mktemp -d)
  STUB_DIR=$SANDBOX/bin
  CALL_LOG=$SANDBOX/calls.log
  HOME_DIR=$SANDBOX/home
  mkdir -p "$STUB_DIR" "$HOME_DIR" "$SANDBOX/exits"
  : > "$CALL_LOG"
  local name
  for name in "${SYSTEM_COMMANDS[@]}"; do
    stub "$name"
  done
  # luajit only computes, so scripts that build a file with it get the real one.
  ln -s "$REAL_LUAJIT" "$STUB_DIR/luajit"
}

run_in_sandbox() {
  env -i HOME="$HOME_DIR" PATH="$STUB_DIR:$GUARD_DIR:/usr/bin:/bin" CALL_LOG="$CALL_LOG" "$@"
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
