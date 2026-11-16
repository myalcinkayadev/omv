#!/usr/bin/env bash
# Usage: claude-usage.sh add|remove
# Adds or removes the one line in ~/.claude/statusline-wrapper.sh that feeds the bar.
# The wrapper is yours and stays out of this repo, so nothing else in it changes.

set -euo pipefail

readonly WRAPPER=$HOME/.claude/statusline-wrapper.sh
readonly MARKER='# omv bar usage'
readonly INPUT_LINE='input=$(cat)'
readonly USAGE_LINE='printf '"'"'%s'"'"' "$input" | "$HOME/.claude/bar-usage.sh" >/dev/null 2>&1 & '"$MARKER"

replace_wrapper() {
  local temporary mode
  mode=$(stat -f %Lp "$WRAPPER")
  temporary=$(mktemp "$WRAPPER.XXXXXX")
  cat > "$temporary"
  chmod "$mode" "$temporary"
  mv "$temporary" "$WRAPPER"
}

add_line() {
  if [ ! -e "$WRAPPER" ]; then
    echo "claude-usage.sh: no status line wrapper found, so the bar's usage item will stay hidden."
    return 0
  fi
  grep -qF "$MARKER" "$WRAPPER" && return 0
  if ! grep -qxF "$INPUT_LINE" "$WRAPPER"; then
    echo "claude-usage.sh: $WRAPPER has no '$INPUT_LINE' line, so it was left unchanged."
    return 0
  fi
  awk -v input="$INPUT_LINE" -v usage="$USAGE_LINE" '{ print } $0 == input && !done { print usage; done = 1 }' "$WRAPPER" | replace_wrapper
}

remove_line() {
  [ -e "$WRAPPER" ] || return 0
  grep -qF "$MARKER" "$WRAPPER" || return 0
  grep -vF "$MARKER" "$WRAPPER" | replace_wrapper
}

case ${1:-} in
  add) add_line ;;
  remove) remove_line ;;
  *)
    echo "usage: claude-usage.sh add|remove" >&2
    exit 2
    ;;
esac
