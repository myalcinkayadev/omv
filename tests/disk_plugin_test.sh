#!/usr/bin/env bash
# Behavior of the bar's disk item: hidden while there's room, the free space when it's low,
# and a click opens the Disk card.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/disk.sh

# df -k / answers with the given total and available KiB.
stub_df() {
  cat > "$STUB_DIR/df" <<STUB
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk3s1s1 %s 1 %s 1%% /\n' "$1" "$2"
STUB
  chmod +x "$STUB_DIR/df"
}

draw() {
  run_in_sandbox NAME=disk SENDER=routine "$PLUGIN"
}

opens_disk_card_on_click() {
  stub hs
  run_in_sandbox NAME=disk SENDER=mouse.clicked "$PLUGIN"
  assert_called "^hs -c omvToggleDisk\(\)$"
}

hides_when_there_is_room() {
  stub_df 482797652 177925936
  draw
  assert_called '^sketchybar --set disk drawing=off$'
}

shows_free_space_below_20_gb() {
  # 100 GB disk with 15 GB free: over 10%, but under 20 GB.
  stub_df 97656250 14648437
  draw
  assert_called '^sketchybar --set disk drawing=on label=15 GB$'
}

shows_free_space_below_10_percent_of_a_large_disk() {
  # 4 TB disk with 300 GB free: over 20 GB, but under 10%.
  stub_df 3906250000 292968750
  draw
  assert_called '^sketchybar --set disk drawing=on label=300 GB$'
}

stays_hidden_when_df_fails() {
  stub df 1
  draw
  assert_called '^sketchybar --set disk drawing=off$'
}

fits_the_bar_after_drawing() {
  stub_df 195312500 14648437
  draw
  assert_called '^sketchybar --trigger bar_fit$'
}

run_case "should open the Disk card on a click" opens_disk_card_on_click
run_case "should hide the item when there is room" hides_when_there_is_room
run_case "should show free GB when free space is below 20 GB" shows_free_space_below_20_gb
run_case "should show free GB when free space is below 10% of a large disk" shows_free_space_below_10_percent_of_a_large_disk
run_case "should stay hidden when df fails" stays_hidden_when_df_fails
run_case "should fit the bar after drawing the item" fits_the_bar_after_drawing
finish
