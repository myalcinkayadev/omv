#!/bin/sh
# Shows CPU and memory only while the Mac is busy: CPU over 80% of all cores, or macOS's
# memory pressure at warn or critical. A click opens the hungry-processes card.
# Runs every 10 seconds, so each run is one ps, one sysctl and one awk; the bar is only
# set, and bar_fit only run, when the label changes.

# sysctl lives in /usr/sbin, which SketchyBar's PATH may lack.
PATH="$PATH:/usr/sbin"

if [ "${SENDER:-}" = mouse.clicked ]; then
  "${0%/*}/../hs.sh" 'omvToggleProcesses()'
  exit 0
fi

# The last label drawn, empty while hidden, so an unchanged one costs no sketchybar call.
state_file="$HOME/.local/state/omv/system-load"

# Each process's share of one core; summed, it's out of 100% per core.
shares=$(ps -A -o %cpu= 2>/dev/null)
# "<cores>\n<pressure level>": 1 normal, 2 warn, 4 critical.
system=$(sysctl -n hw.ncpu kern.memorystatus_vm_pressure_level 2>/dev/null)

label=""
if [ -n "$shares" ] && [ -n "$system" ]; then
  label=$(printf '%s\n--\n%s\n' "$shares" "$system" | awk '
    $0 == "--" { after = 1; next }
    !after { sum += $1; next }
    cores == "" { cores = $1; next }
    { pressure = $1 }
    END {
      if (cores <= 0) exit
      share = sum / cores
      if (share > 80) out = sprintf("CPU %d%%", share + 0.5)
      memory = pressure == 2 ? "mem high" : pressure == 4 ? "mem critical" : ""
      if (memory != "") out = out == "" ? memory : out ", " memory
      print out
    }')
fi

last=""
[ -r "$state_file" ] && read -r last < "$state_file"
# A routine run with nothing new leaves the bar alone; any other sender, such as SketchyBar
# starting or the Mac waking, draws it again.
if [ "${SENDER:-}" = routine ] && [ "$label" = "$last" ]; then
  exit 0
fi

mkdir -p "${state_file%/*}"
printf '%s\n' "$label" > "$state_file"
if [ -z "$label" ]; then
  sketchybar --set "$NAME" drawing=off --trigger bar_fit
else
  sketchybar --set "$NAME" drawing=on label="$label" --trigger bar_fit
fi
