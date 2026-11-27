#!/usr/bin/env bash
# Behavior of askpass.sh, which asks for the password sudo needs while omv Setup installs.

source "$(dirname "$0")/lib.sh"

readonly ASKPASS=$REPO_DIR/install/askpass.sh

# osascript answers with what the user typed, or fails as it does on Cancel.
dialog_answers() {
  own_stub osascript
  printf '#!/bin/sh\necho "osascript $*" >> "%s"\nprintf "%%s\\n" "%s"\n' "$CALL_LOG" "$1" > "$STUB_DIR/osascript"
  chmod +x "$STUB_DIR/osascript"
}

prints_the_password() {
  dialog_answers 'hunter 2'
  [ "$(run_in_sandbox "$ASKPASS" 'Password:')" = 'hunter 2' ] || fail 'wrong password printed'
}

asks_with_a_hidden_answer() {
  dialog_answers secret
  run_in_sandbox "$ASKPASS" 'Password:' >/dev/null
  assert_called 'with hidden answer'
}

fails_on_cancel() {
  stub osascript 1
  assert_exit_nonzero run_in_sandbox "$ASKPASS" 'Password:'
}

run_case "should print what was typed when the dialog is answered" prints_the_password
run_case "should hide the typing when asking" asks_with_a_hidden_answer
run_case "should fail when the dialog is cancelled" fails_on_cancel

finish
