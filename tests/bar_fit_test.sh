#!/usr/bin/env bash
# Behavior of the script that keeps the right side of the bar clear of the notch.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/bar_fit.sh

# The stubbed bar is one 1512pt display, so the notch's right edge is 856pt. Each item's
# --query answer is $SANDBOX/<item>.json, built from its left edge and width.
stub_bar() {
  cat > "$STUB_DIR/sketchybar" <<STUB
#!/bin/sh
echo "sketchybar \$*" >> "$CALL_LOG"
case "\$1 \$2" in
  "--query displays") echo '[{"arrangement-id":1,"frame":{"x":0,"y":0,"w":1512,"h":982}}]' ;;
  --query\ *) cat "$SANDBOX/\$2.json" 2>/dev/null || echo '{"geometry":{"drawing":"off"},"bounding_rects":{}}' ;;
esac
exit 0
STUB
  chmod +x "$STUB_DIR/sketchybar"
}

item() {
  printf '{"geometry":{"drawing":"on"},"bounding_rects":{"display-1":{"origin":[%s,0],"size":[%s,36]}}}' "$2" "$3" > "$SANDBOX/$1.json"
}

# The fixed items on the right, ending at the clock.
status_items() {
  item wifi 1250 40
  item volume 1290 40
  item battery 1330 40
  item clock 1370 132
}

fit() {
  run_in_sandbox "$PLUGIN"
}

fits_already() {
  stub_bar; status_items
  item claude_usage 1088 162
  fit
  assert_not_called 'drawing=off'
}

shrinks_claude_first() {
  stub_bar; status_items
  item claude_usage 1088 162
  item reminder 900 90
  item meeting 840 60
  fit
  assert_called '^sketchybar --set claude_usage label.drawing=off$'
}

keeps_meeting_when_claude_is_enough() {
  stub_bar; status_items
  item claude_usage 1088 162
  item reminder 900 90
  item meeting 840 60
  fit
  assert_not_called '^sketchybar --set meeting label.drawing=off$'
}

then_shrinks_meeting() {
  stub_bar; status_items
  item claude_usage 1088 162
  item keep_awake 1050 38
  item reminder 700 350
  item meeting 640 60
  fit
  assert_called '^sketchybar --set meeting label.drawing=off$'
}

hides_claude_last() {
  stub_bar; status_items
  item claude_usage 1088 162
  item reminder 520 568
  item meeting 440 80
  fit
  assert_called '^sketchybar --set claude_usage icon.drawing=off$'
}

restores_when_room() {
  stub_bar; status_items
  item claude_usage 1088 162
  fit
  assert_called '^sketchybar --set claude_usage icon.drawing=on label.drawing=on --set meeting label.drawing=on$'
}

never_hides_keep_awake_or_reminder() {
  stub_bar; status_items
  item claude_usage 1088 162
  item reminder 520 568
  item meeting 440 80
  fit
  assert_not_called '--set (keep_awake|reminder) '
}

ignores_hidden_items() {
  stub_bar; status_items
  item claude_usage 1088 162
  printf '{"geometry":{"drawing":"off"},"bounding_rects":{"display-1":{"origin":[100,0],"size":[90,36]}}}' > "$SANDBOX/meeting.json"
  fit
  assert_not_called 'drawing=off'
}

run_case 'should change nothing when everything fits' fits_already
run_case "should shrink Claude to its logo first" shrinks_claude_first
run_case 'should keep the meeting time when shrinking Claude is enough' keeps_meeting_when_claude_is_enough
run_case 'should then show the meeting as just its icon' then_shrinks_meeting
run_case 'should hide Claude completely last' hides_claude_last
run_case 'should bring back every item before measuring' restores_when_room
run_case 'should never hide keep-awake or the reminder' never_hides_keep_awake_or_reminder
run_case 'should leave hidden items out of the measure' ignores_hidden_items
finish
