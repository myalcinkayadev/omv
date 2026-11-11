#!/bin/sh
# Claude Code hook. "wait" marks the session as waiting for you (Stop, and a Notification
# that asks for you), and "clear" unmarks it (UserPromptSubmit, PostToolUse, SessionEnd).
# Saves only Claude's PID, its terminal and the folder name, for the bar. Prints nothing,
# since Claude reads hook output, and always exits 0.

PATH="$PATH:/opt/homebrew/bin"
state_dir="$HOME/.local/state/omv/claude-waiting"

input=$(cat)
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
# The id names a file, so anything that could be a path is refused.
case $session in
  '' | *[!A-Za-z0-9-]*) exit 0 ;;
esac
file="$state_dir/$session"

notify_bar() {
  sketchybar --trigger claude_waiting_change >/dev/null 2>&1
}

clear_session() {
  [ -e "$file" ] || exit 0
  rm -f "$file"
  notify_bar
}

# The hook runs without a terminal; Claude, an ancestor, has one. Prints "<pid> <tty>".
claude_terminal() {
  pid=$PPID
  hops=0
  while [ "$pid" -gt 1 ] 2>/dev/null && [ "$hops" -lt 10 ]; do
    # shellcheck disable=SC2046
    set -- $(ps -o tty=,ppid= -p "$pid" 2>/dev/null)
    [ -n "${1:-}" ] || break
    if [ "$1" != '??' ]; then
      echo "$pid /dev/$1"
      return
    fi
    pid=${2:-1}
    hops=$((hops + 1))
  done
  echo "$PPID -"
}

# Stop has no notification type, and neither does a notification from an older Claude Code.
# Other notifications count only when they ask for you: one that an agent finished or
# that sign-in worked would mark a session that is still working.
asks_for_you() {
  case $(printf '%s' "$input" | jq -r '.notification_type // empty' 2>/dev/null) in
    '' | permission_prompt | elicitation_dialog | elicitation_url_dialog | agent_needs_input) return 0 ;;
    # Sent a minute after Claude stops, so a session already recorded keeps its start time.
    idle_prompt) [ ! -e "$file" ] ;;
    *) return 1 ;;
  esac
}

wait_session() {
  asks_for_you || exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
  folder=$(printf '%s' "${cwd##*/}" | tr '\t\n' '  ')
  # shellcheck disable=SC2046
  set -- $(claude_terminal)
  mkdir -p "$state_dir" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${folder:-Claude}" "$(date +%s)" > "$file" 2>/dev/null
  notify_bar
}

case ${1:-} in
  wait) wait_session ;;
  clear) clear_session ;;
esac
exit 0
