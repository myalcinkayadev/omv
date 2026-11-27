#!/usr/bin/env bash
# Behavior of translate.sh: it builds the Swift helper once and hands it the arguments and
# the text to translate.

source "$(dirname "$0")/lib.sh"

readonly TRANSLATE=$REPO_DIR/config/hammerspoon/translate.sh

# swiftc "builds" a helper that logs its arguments and the text it reads, then answers ok.
stub_swiftc() {
  own_stub swiftc
  cat > "$STUB_DIR/swiftc" <<STUB
#!/bin/sh
echo "swiftc \$*" >> "$CALL_LOG"
for last; do :; done
printf '#!/bin/sh\necho "helper \$*" >> "%s"\necho "text \$(cat)" >> "%s"\necho ok\n' "$CALL_LOG" "$CALL_LOG" > "\$last"
chmod +x "\$last"
STUB
  chmod +x "$STUB_DIR/swiftc"
}

passes_the_arguments() {
  stub_swiftc
  echo merhaba | run_in_sandbox "$TRANSLATE" tr en > /dev/null
  assert_called '^helper tr en$'
}

passes_the_text() {
  stub_swiftc
  echo merhaba | run_in_sandbox "$TRANSLATE" tr en > /dev/null
  assert_called '^text merhaba$'
}

prints_the_answer() {
  stub_swiftc
  [ "$(echo merhaba | run_in_sandbox "$TRANSLATE" detect)" = ok ] || fail 'no answer printed'
}

builds_the_helper_once() {
  stub_swiftc
  echo a | run_in_sandbox "$TRANSLATE" detect > /dev/null
  : > "$CALL_LOG"
  echo a | run_in_sandbox "$TRANSLATE" detect > /dev/null
  assert_not_called '^swiftc'
}

fails_when_the_helper_cannot_build() {
  own_stub swiftc
  printf '#!/bin/sh\nexit 1\n' > "$STUB_DIR/swiftc"
  chmod +x "$STUB_DIR/swiftc"
  echo a | assert_exit_nonzero run_in_sandbox "$TRANSLATE" detect
}

run_case 'should hand the helper its arguments' passes_the_arguments
run_case 'should hand the helper the text to translate' passes_the_text
run_case "should print the helper's answer" prints_the_answer
run_case 'should build the helper once and reuse it' builds_the_helper_once
run_case "should exit non-zero when the helper can't be built" fails_when_the_helper_cannot_build
finish
