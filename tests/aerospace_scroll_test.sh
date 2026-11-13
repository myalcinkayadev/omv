#!/usr/bin/env bash
# Behavior of scrolling over the workspace numbers.

source "$(dirname "$0")/lib.sh"

readonly SCROLL=$REPO_DIR/sketchybar/.config/sketchybar/plugins/aerospace_scroll.sh

stub_focused() {
  cat > "$STUB_DIR/aerospace" <<STUB
#!/bin/sh
echo "aerospace \$*" >> "$CALL_LOG"
[ "\$*" = "list-workspaces --focused" ] && echo $1
exit 0
STUB
  chmod +x "$STUB_DIR/aerospace"
}

scroll() {
  run_in_sandbox SCROLL_DELTA="$1" "$SCROLL"
}

write_stamp() {
  mkdir -p "$HOME_DIR/.local/state/omv"
  echo "$1" > "$HOME_DIR/.local/state/omv/scroll-stamp"
}

goes_next_when_up() {
  stub_focused 2
  scroll 3
  assert_called '^aerospace workspace 3$'
}

goes_previous_when_down() {
  stub_focused 2
  scroll -3
  assert_called '^aerospace workspace 1$'
}

wraps_from_7_to_1() {
  stub_focused 7
  scroll 3
  assert_called '^aerospace workspace 1$'
}

wraps_from_1_to_7() {
  stub_focused 1
  scroll -3
  assert_called '^aerospace workspace 7$'
}

goes_from_6_to_7() {
  stub_focused 6
  scroll 3
  assert_called '^aerospace workspace 7$'
}

ignores_zero_delta() {
  stub_focused 2
  scroll 0
  assert_not_called '^aerospace workspace'
}

ignores_decimal_zero_delta() {
  stub_focused 2
  scroll 0.0
  assert_not_called '^aerospace workspace'
}

# A stamp in the far future always counts as "just scrolled", so no timing is involved.
ignores_second_scroll_within_limit() {
  stub_focused 2
  write_stamp 99999999999999
  scroll 3
  assert_not_called '^aerospace workspace'
}

accepts_scroll_after_limit() {
  stub_focused 2
  write_stamp 1000
  scroll 3
  assert_called '^aerospace workspace 3$'
}

ignores_unknown_focus() {
  stub_focused ""
  scroll 3
  assert_not_called '^aerospace workspace'
}

run_case 'should go to the next workspace when scrolling up' goes_next_when_up
run_case 'should go to the previous workspace when scrolling down' goes_previous_when_down
run_case 'should wrap from 7 to 1 when scrolling up on 7' wraps_from_7_to_1
run_case 'should wrap from 1 to 7 when scrolling down on 1' wraps_from_1_to_7
run_case 'should go from 6 to the dev workspace 7 when scrolling up' goes_from_6_to_7
run_case 'should do nothing when the scroll delta is zero' ignores_zero_delta
run_case 'should do nothing when the scroll delta is a decimal zero' ignores_decimal_zero_delta
run_case 'should ignore a second scroll within 300ms' ignores_second_scroll_within_limit
run_case 'should accept a scroll after the limit' accepts_scroll_after_limit
run_case 'should do nothing when the focused workspace is unknown' ignores_unknown_focus
finish
