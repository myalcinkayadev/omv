#!/bin/sh
# Shows Claude Code sessions waiting for you, as the folder of the one to answer first, then
# +N for the others. A session asking for approval comes first and is marked "? omv"; then
# the ones done, the one waiting longest first. Working sessions stay out of it.
# claude-waiting.sh, a Claude hook, saves them. A session whose Claude has ended is dropped.
# A click focuses the session's terminal; see features/waiting.lua.

state_dir="$HOME/.local/state/omv/claude-sessions"
tab=$(printf '\t')

if [ "${SENDER:-}" = mouse.clicked ]; then
  hs -c 'omvFocusClaude()'
  exit 0
fi

# "<rank><TAB><since><TAB><label>" per live waiting session: asking (rank 0) before done
# (rank 1), then the longest waiting first. A file from before states existed is done.
waiting() {
  for file in "$state_dir"/*; do
    [ -f "$file" ] || continue
    IFS="$tab" read -r pid _ folder since state < "$file"
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$file"
      continue
    fi
    case ${state:-done} in
      asks) printf '0\t%s\t? %s\n' "$since" "$(short "$folder")" ;;
      done) printf '1\t%s\t%s\n' "$since" "$(short "$folder")" ;;
    esac
  done | sort -t "$tab" -k1,1n -k2,2n
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
label=$(printf '%s\n' "$sessions" | head -n 1 | cut -f 3)
[ "$count" -gt 1 ] && label="$label +$((count - 1))"

sketchybar --set "$NAME" drawing=on "label=$label"
# The label's width changes, so the right side may need to give way before the notch.
sketchybar --trigger bar_fit
