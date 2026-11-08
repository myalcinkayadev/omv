#!/usr/bin/env bash
# Behavior of the bar's battery item: a click opens the Battery card.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/battery.sh

opens_battery_card_on_click() {
  stub hs
  run_in_sandbox NAME=battery SENDER=mouse.clicked "$PLUGIN"
  assert_called "^hs -c omvToggleBattery\(\)$"
}

# pmset answers with the given source and battery line.
stub_pmset() {
  cat > "$STUB_DIR/pmset" <<STUB
#!/bin/sh
printf "Now drawing from '%s'\n -InternalBattery-0 (id=1)\t%s present: true\n" "$1" "$2"
STUB
  chmod +x "$STUB_DIR/pmset"
}

draw() {
  run_in_sandbox NAME=battery SENDER=routine "$PLUGIN"
}

leaves_card_closed_on_timer() {
  stub hs
  stub_pmset 'Battery Power' '78%; discharging; 6:05 remaining'
  draw
  assert_not_called '^hs '
}

draws_upright_battery_by_tens() {
  stub_pmset 'Battery Power' '78%; discharging; 6:05 remaining'
  draw
  assert_called '^sketchybar --set battery icon=󰂀 label=78%$'
}

draws_full_battery() {
  stub_pmset 'Battery Power' '100%; discharging; 9:00 remaining'
  draw
  assert_called '^sketchybar --set battery icon=󰁹 label=100%$'
}

draws_empty_battery_below_ten() {
  stub_pmset 'Battery Power' '5%; discharging; 0:20 remaining'
  draw
  assert_called '^sketchybar --set battery icon=󰂎 label=5%$'
}

draws_charging_battery_on_power() {
  stub_pmset 'AC Power' '41%; charging; 1:12 remaining'
  draw
  assert_called '^sketchybar --set battery icon=󰂄 label=41%$'
}

run_case "should open the Battery card on a click" opens_battery_card_on_click
run_case "should leave the card closed when the timer redraws the icon" leaves_card_closed_on_timer
run_case "should draw an upright battery filled to the tens below its charge" draws_upright_battery_by_tens
run_case "should draw a full battery at 100%" draws_full_battery
run_case "should draw an empty battery below 10%" draws_empty_battery_below_ten
run_case "should draw a charging battery on power" draws_charging_battery_on_power
finish
