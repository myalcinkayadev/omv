#!/bin/sh
# Claude Code hook. Records each session's state for the bar and the Agents card:
#   working  you sent a prompt, or a tool ran (UserPromptSubmit, PostToolUse)
#   asks     Claude waits for your approval or answer (a Notification that asks for you)
#   done     Claude finished and waits for your next prompt (Stop)
# SessionEnd removes the session. It acts on the event's name, so the argument it was
# installed with, "wait" or "clear", no longer matters.
# Saves only Claude's PID, its terminal, the folder name, when the session entered its
# state, and the state. Prints nothing, since Claude reads hook output, and always exits 0.

PATH="$PATH:/opt/homebrew/bin"
state_dir="$HOME/.local/state/omv/claude-sessions"

input=$(cat)
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
# The id names a file, so anything that could be a path is refused.
case $session in
  '' | *[!A-Za-z0-9-]*) exit 0 ;;
esac
file="$state_dir/$session"

field() {
  printf '%s' "$input" | jq -r ".$1 // empty" 2>/dev/null
}

# The state a session's file holds, empty when none. A file from before states existed is done.
saved_state() {
  [ -e "$file" ] || return 0
  state=$(cut -f5 "$file")
  echo "${state:-done}"
}

# The state an event leads to, "end" to remove the session, or empty to change nothing.
# Notifications count only when they ask for you: one that an agent finished or that
# sign-in worked would mark a session that is still working. One without a type comes
# from an older Claude Code, and most often asks for approval.
next_state() {
  case $(field hook_event_name) in
    UserPromptSubmit | PostToolUse) echo working ;;
    Stop) echo done ;;
    SessionEnd) echo end ;;
    Notification)
      case $(field notification_type) in
        '' | permission_prompt | elicitation_dialog | elicitation_url_dialog | agent_needs_input) echo asks ;;
        # Sent a minute after Claude stops, so it only fills in a session not yet recorded.
        idle_prompt) [ -e "$file" ] || echo done ;;
      esac
      ;;
  esac
}

# The bar shows only sessions waiting for you, so it hears about a change only when one
# starts or stops waiting, or turns between asking and done.
notify_bar() {
  [ "$1" = working ] && [ "$2" = working ] && return
  [ -z "$1" ] && [ "$2" = working ] && return
  [ "$1" = working ] && [ "$2" = end ] && return
  [ -z "$1" ] && [ "$2" = end ] && return
  sketchybar --trigger claude_waiting_change >/dev/null 2>&1
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

save() {
  cwd=$(field cwd)
  folder=$(printf '%s' "${cwd##*/}" | tr '\t\n' '  ')
  # shellcheck disable=SC2046
  set -- $(claude_terminal)
  mkdir -p "$state_dir" 2>/dev/null
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "${folder:-Claude}" "$(date +%s)" "$state" > "$file" 2>/dev/null
}

state=$(next_state)
[ -n "$state" ] || exit 0
before=$(saved_state)
# A session that stays in its state keeps its file, and with it when it entered the state.
[ "$state" = "$before" ] && exit 0

if [ "$state" = end ]; then
  [ -n "$before" ] || exit 0
  rm -f "$file" "$state_dir/.seen-$session"
else
  save
fi
notify_bar "$before" "$state"
exit 0
