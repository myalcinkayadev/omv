#!/bin/sh
# Shows Claude Code sessions waiting for you, as the folder of the one waiting longest,
# then +N for the others. claude-waiting.sh, a Claude hook, saves them. A session
# whose Claude has ended is dropped. A click focuses the session's terminal; see init.lua.

state_dir="$HOME/.local/state/omv/claude-waiting"
tab=$(printf '\t')

if [ "${SENDER:-}" = mouse.clicked ]; then
  hs -c 'omvFocusClaude()'
  exit 0
fi

# "<since><TAB><folder>" per live session, the longest waiting first.
waiting() {
  for file in "$state_dir"/*; do
    [ -f "$file" ] || continue
    IFS="$tab" read -r pid _ folder since < "$file"
    if kill -0 "$pid" 2>/dev/null; then
      printf '%s\t%s\n' "$since" "$folder"
    else
      rm -f "$file"
    fi
  done | sort -n
}

# Cut at 12 characters, counted in UTF-8 so a Turkish letter is never split.
short() {
  printf '%s' "$1" | LC_ALL=en_US.UTF-8 awk '{ if (length($0) > 12) print substr($0, 1, 11) "…"; else print }'
}

sessions=$(waiting)
if [ -z "$sessions" ]; then
  sketchybar --set "$NAME" drawing=off
  sketchybar --trigger bar_fit
  exit 0
fi

count=$(printf '%s\n' "$sessions" | wc -l | tr -d ' ')
label="$(short "$(printf '%s\n' "$sessions" | head -n 1 | cut -f 2)")"
[ "$count" -gt 1 ] && label="$label +$((count - 1))"

sketchybar --set "$NAME" drawing=on "label=$label"
# The label's width changes, so the right side may need to give way before the notch.
sketchybar --trigger bar_fit
