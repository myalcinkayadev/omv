#!/usr/bin/env bash
# Behavior of the bar's system load item: hidden while the Mac is idle, the CPU share or
# memory pressure while it's busy, and a click opens the hungry-processes card.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/config/sketchybar/.config/sketchybar/plugins/system_load.sh

# ps -A -o %cpu= prints each given share on its own line.
stub_ps() {
  printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "$*" > "$STUB_DIR/ps"
  chmod +x "$STUB_DIR/ps"
}

# sysctl -n hw.ncpu kern.memorystatus_vm_pressure_level prints the cores, then the level.
stub_sysctl() {
  printf '#!/bin/sh\nprintf "%%s\\n%%s\\n" %s %s\n' "$1" "$2" > "$STUB_DIR/sysctl"
  chmod +x "$STUB_DIR/sysctl"
}

draw() {
  run_in_sandbox NAME=system_load SENDER="${1:-forced}" "$PLUGIN"
}

hides_when_idle() {
  stub_ps 120.0 30.5 0.0
  stub_sysctl 10 1
  draw
  assert_called '^sketchybar --set system_load drawing=off --trigger bar_fit$'
}

shows_cpu_share_when_busy() {
  # 920% over 10 cores is 92%.
  stub_ps 800.0 100.0 20.0
  stub_sysctl 10 1
  draw
  assert_called '^sketchybar --set system_load drawing=on label=CPU 92% --trigger bar_fit$'
}

hides_at_exactly_80_percent() {
  stub_ps 600.0 200.0
  stub_sysctl 10 1
  draw
  assert_called '^sketchybar --set system_load drawing=off'
}

shows_cpu_just_over_80_percent() {
  stub_ps 600.0 200.1
  stub_sysctl 10 1
  draw
  assert_called '^sketchybar --set system_load drawing=on label=CPU 80%'
}

shows_memory_warn() {
  stub_ps 10.0
  stub_sysctl 10 2
  draw
  assert_called '^sketchybar --set system_load drawing=on label=mem high'
}

shows_memory_critical() {
  stub_ps 10.0
  stub_sysctl 10 4
  draw
  assert_called '^sketchybar --set system_load drawing=on label=mem critical'
}

shows_both() {
  stub_ps 950.0
  stub_sysctl 10 4
  draw
  assert_called '^sketchybar --set system_load drawing=on label=CPU 95%, mem critical'
}

hides_when_ps_fails() {
  stub ps 1
  stub_sysctl 10 4
  draw
  assert_called '^sketchybar --set system_load drawing=off'
}

hides_when_ps_prints_nothing() {
  stub_ps ''
  stub_sysctl 10 4
  draw
  assert_called '^sketchybar --set system_load drawing=off'
}

hides_when_sysctl_fails() {
  stub_ps 950.0
  stub sysctl 1
  draw
  assert_called '^sketchybar --set system_load drawing=off'
}

skips_the_bar_when_unchanged() {
  stub_ps 950.0
  stub_sysctl 10 1
  draw routine
  : > "$CALL_LOG"
  draw routine
  assert_not_called '^sketchybar'
}

draws_on_change() {
  stub_ps 950.0
  stub_sysctl 10 1
  draw routine
  stub_ps 10.0
  draw routine
  assert_called '^sketchybar --set system_load drawing=off --trigger bar_fit$'
}

redraws_when_not_routine() {
  stub_ps 950.0
  stub_sysctl 10 1
  draw routine
  : > "$CALL_LOG"
  draw system_woke
  assert_called '^sketchybar --set system_load drawing=on label=CPU 95%'
}

opens_processes_card_on_click() {
  stub hs
  run_in_sandbox NAME=system_load SENDER=mouse.clicked "$PLUGIN"
  assert_called '^hs -c omvToggleProcesses\(\)$'
}

run_case "should stay hidden when CPU is under 80% and memory pressure is normal" hides_when_idle
run_case "should show the CPU share when the summed ps CPU over the core count passes 80%" shows_cpu_share_when_busy
run_case "should stay hidden when the CPU share is exactly 80%" hides_at_exactly_80_percent
run_case "should show the CPU share when it is just over 80%" shows_cpu_just_over_80_percent
run_case "should show memory pressure when the level is warn" shows_memory_warn
run_case "should show memory pressure when the level is critical" shows_memory_critical
run_case "should show both when both are busy" shows_both
run_case "should stay hidden when ps fails" hides_when_ps_fails
run_case "should stay hidden when ps prints nothing" hides_when_ps_prints_nothing
run_case "should stay hidden when sysctl fails" hides_when_sysctl_fails
run_case "should leave the bar alone when a routine run finds the same label" skips_the_bar_when_unchanged
run_case "should redraw the item when the label changes" draws_on_change
run_case "should redraw the item when SketchyBar starts or the Mac wakes" redraws_when_not_routine
run_case "should open the processes card on a click" opens_processes_card_on_click
finish
