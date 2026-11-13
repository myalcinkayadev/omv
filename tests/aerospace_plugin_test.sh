#!/usr/bin/env bash
# Behavior of the SketchyBar plugin that highlights AeroSpace workspaces.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/aerospace.sh
readonly FOCUSED_STYLE='background.color=0xffffffff icon.color=0xff000000'
readonly VISIBLE_STYLE='background.color=0xff3a3a3a icon.color=0xffffffff'
readonly IDLE_STYLE='background.color=0x00000000 icon.color=0xff7a7a7a'

# Answers only the two queries the plugin makes, so an unexpected query shows up as empty output.
stub_aerospace() {
  local focused=$1 visible=$2
  cat > "$STUB_DIR/aerospace" <<EOF
#!/bin/sh
case "\$*" in
  "list-workspaces --focused") printf '%s\n' "$focused" ;;
  "list-workspaces --monitor all --visible") printf '%s\n' "$visible" ;;
esac
EOF
  chmod +x "$STUB_DIR/aerospace"
}

highlights_focused_from_event() {
  stub_aerospace "" "3"
  run_in_sandbox FOCUSED_WORKSPACE=3 "$PLUGIN"
  assert_called "--set space\.3 $FOCUSED_STYLE"
}

dims_other_workspaces() {
  stub_aerospace "" "3"
  run_in_sandbox FOCUSED_WORKSPACE=3 "$PLUGIN"
  local number
  for number in 1 2 4 5 6; do
    assert_called "--set space\.$number $IDLE_STYLE"
  done
}

queries_focused_without_event() {
  stub_aerospace "2" "2"
  run_in_sandbox "$PLUGIN"
  assert_called "--set space\.2 $FOCUSED_STYLE"
}

marks_visible_on_unfocused_monitor() {
  stub_aerospace "" "3
4"
  run_in_sandbox FOCUSED_WORKSPACE=3 "$PLUGIN"
  assert_called "--set space\.4 $VISIBLE_STYLE"
}

survives_empty_aerospace_output() {
  stub_aerospace "" ""
  assert_exit_zero run_in_sandbox "$PLUGIN"
}

highlights_workspace_6() {
  stub_aerospace "" "6"
  run_in_sandbox FOCUSED_WORKSPACE=6 "$PLUGIN"
  assert_called "--set space\.6 $FOCUSED_STYLE"
}

highlights_the_dev_workspace() {
  stub_aerospace "" "7"
  run_in_sandbox FOCUSED_WORKSPACE=7 "$PLUGIN"
  assert_called "--set space\.7 $FOCUSED_STYLE"
}

ignores_unknown_workspace() {
  stub_aerospace "" ""
  run_in_sandbox FOCUSED_WORKSPACE=9 "$PLUGIN"
  assert_not_called '^sketchybar'
}

run_case 'should highlight workspace 3 when the event supplies FOCUSED_WORKSPACE=3' highlights_focused_from_event
run_case 'should dim every other workspace when workspace 3 is focused' dims_other_workspaces
run_case 'should query aerospace for the focused workspace when the script runs without an event' queries_focused_without_event
run_case 'should mark a workspace as visible when it is shown on the unfocused monitor' marks_visible_on_unfocused_monitor
run_case 'should highlight workspace 6 when it is focused' highlights_workspace_6
run_case 'should exit without error when aerospace returns nothing' survives_empty_aerospace_output
run_case 'should highlight the dev workspace 7 when it is focused' highlights_the_dev_workspace
run_case 'should leave items unchanged when the focused workspace is outside 1-7' ignores_unknown_workspace
uses_the_theme_colors() {
  stub_aerospace 2 '2'
  mkdir -p "$HOME_DIR/.local/state/omv/theme"
  printf 'WHITE=0xffc0caf5\nMUTED=0xff414868\nBLACK=0xff1a1b26\nGRAY=0xff3b3d4f\n' > "$HOME_DIR/.local/state/omv/theme/colors.sh"
  run_in_sandbox "$PLUGIN"
  assert_called '--set space\.2 background.color=0xffc0caf5 icon.color=0xff1a1b26'
}

run_case "should use the theme's colours when a theme was chosen" uses_the_theme_colors
finish
