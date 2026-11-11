#!/usr/bin/env bash
# Behavior of the script that keeps the right side of the bar clear of the notch.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/bar_fit.sh

readonly ONE_DISPLAY='[{"arrangement-id":1,"frame":{"x":0,"y":0,"w":1512,"h":982}}]'
# A 2560pt main display with the 1512pt one placed to its left, so its frame starts at -1512.
readonly TWO_DISPLAYS='[{"arrangement-id":1,"frame":{"x":0,"y":0,"w":2560,"h":1440}},{"arrangement-id":2,"frame":{"x":-1512,"y":458,"w":1512,"h":982}}]'

# The stubbed bar is one 1512pt display unless told otherwise, so the notch's right edge
# is 856pt. Each item's --query answer is $SANDBOX/<item>.json, built from its left edge and width.
stub_bar() {
  cat > "$STUB_DIR/sketchybar" <<STUB
#!/bin/sh
echo "sketchybar \$*" >> "$CALL_LOG"
case "\$1 \$2" in
  "--query displays") echo '${1:-$ONE_DISPLAY}' ;;
  --query\ *) cat "$SANDBOX/\$2.json" 2>/dev/null || echo '{"geometry":{"drawing":"off"},"bounding_rects":{}}' ;;
esac
exit 0
STUB
  chmod +x "$STUB_DIR/sketchybar"
}

item() {
  printf '{"geometry":{"drawing":"on"},"bounding_rects":{"display-1":{"origin":[%s,0],"size":[%s,36]}}}' "$2" "$3" > "$SANDBOX/$1.json"
}

# An item on both of TWO_DISPLAYS, from its left edge on the 1512pt one. SketchyBar counts
# every edge from the main display's corner, so on the display to the left it is negative.
item_on_both() {
  printf '{"geometry":{"drawing":"on"},"bounding_rects":{"display-1":{"origin":[%s,0],"size":[%s,36]},"display-2":{"origin":[%s,0],"size":[%s,36]}}}' \
    "$(($2 + 1048))" "$3" "$(($2 - 1512))" "$3" > "$SANDBOX/$1.json"
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
  item weather 1180 70
  item claude_usage 1140 40
  fit
  assert_not_called 'drawing=off'
}

shrinks_claude_first() {
  stub_bar; status_items
  item claude_usage 1150 90
  item reminder 900 250
  item meeting 840 60
  fit
  assert_called '^sketchybar --set claude_usage label.drawing=off$'
}

keeps_meeting_when_claude_is_enough() {
  stub_bar; status_items
  item claude_usage 1150 90
  item reminder 900 250
  item meeting 840 60
  fit
  assert_not_called '^sketchybar --set meeting label.drawing=off$'
}

shrinks_meeting_first() {
  stub_bar; status_items
  item claude_usage 1210 40
  item reminder 900 310
  item meeting 840 60
  fit
  assert_called '^sketchybar --set meeting label.drawing=off$'
}

keeps_weather_when_meeting_is_enough() {
  stub_bar; status_items
  item claude_usage 1210 40
  item reminder 900 310
  item meeting 840 60
  item weather 1140 70
  fit
  assert_not_called '^sketchybar --set weather label.drawing=off$'
}

then_shrinks_weather() {
  stub_bar; status_items
  item weather 1180 70
  item claude_usage 1140 40
  item reminder 700 440
  item meeting 640 60
  fit
  assert_called '^sketchybar --set weather label.drawing=off$'
}

keeps_logo_when_weather_is_enough() {
  stub_bar; status_items
  item weather 1180 70
  item claude_usage 1140 40
  item reminder 860 280
  item meeting 800 60
  fit
  assert_not_called '^sketchybar --set claude_usage icon.drawing=off$'
}

hides_logo_last() {
  stub_bar; status_items
  item weather 1180 70
  item claude_usage 1140 40
  item reminder 700 440
  item meeting 640 60
  fit
  assert_called '^sketchybar --set claude_usage icon.drawing=off$'
}

restores_when_room() {
  stub_bar; status_items
  item claude_usage 1210 40
  fit
  assert_called '^sketchybar --set claude_usage icon.drawing=on label.drawing=on --set meeting label.drawing=on --set weather label.drawing=on$'
}

never_hides_keep_awake_or_reminder() {
  stub_bar; status_items
  item claude_usage 1210 40
  item reminder 520 690
  item meeting 440 80
  fit
  assert_not_called '--set (keep_awake|reminder) '
}

ignores_hidden_items() {
  stub_bar; status_items
  item claude_usage 1210 40
  printf '{"geometry":{"drawing":"off"},"bounding_rects":{"display-1":{"origin":[100,0],"size":[90,36]}}}' > "$SANDBOX/meeting.json"
  fit
  assert_not_called 'drawing=off'
}

fits_on_a_display_to_the_left() {
  stub_bar "$TWO_DISPLAYS"
  item_on_both clock 1370 132
  item_on_both claude_usage 1210 90
  fit
  assert_not_called 'drawing=off'
}

gives_way_on_a_display_to_the_left() {
  stub_bar "$TWO_DISPLAYS"
  item_on_both clock 1370 132
  item_on_both claude_usage 1150 90
  item_on_both reminder 800 350
  fit
  assert_called '^sketchybar --set claude_usage label.drawing=off$'
}

run_case 'should change nothing when everything fits' fits_already
run_case 'should keep every item when a display placed to the left has room before its notch' fits_on_a_display_to_the_left
run_case 'should give way when a display placed to the left has items reaching its notch' gives_way_on_a_display_to_the_left
run_case "should shrink Claude to its logo first" shrinks_claude_first
run_case 'should keep the meeting time when shrinking Claude is enough' keeps_meeting_when_claude_is_enough
run_case 'should then show the meeting as just its icon' shrinks_meeting_first
run_case 'should keep the weather temperature when shrinking the meeting is enough' keeps_weather_when_meeting_is_enough
run_case 'should then show the weather as just its icon' then_shrinks_weather
run_case 'should keep the Claude logo when shrinking the weather is enough' keeps_logo_when_weather_is_enough
run_case 'should hide the Claude logo last' hides_logo_last
run_case 'should bring back every item before measuring' restores_when_room
run_case 'should never hide keep-awake or the reminder' never_hides_keep_awake_or_reminder
run_case 'should leave hidden items out of the measure' ignores_hidden_items
finish
