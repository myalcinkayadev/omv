#!/usr/bin/env bash
# Usage: claude-hooks.sh add|remove
# Adds or removes the hooks in ~/.claude/settings.json that tell the bar when a Claude Code
# session waits for you. The settings are yours and stay out of this repo: only entries
# that run claude-waiting.sh are touched, and a file jq can't read is left unchanged.

set -euo pipefail

readonly SETTINGS=$HOME/.claude/settings.json
readonly HOOK='$HOME/.claude/claude-waiting.sh'

# Entries are matched by the script's name, so an older form of the line is replaced too.
readonly FILTER='
  def ours: any(.hooks[]?; .command | tostring | contains("claude-waiting.sh"));
  def without_ours: .hooks |= ((. // {}) | with_entries(.value |= map(select(ours | not))) | with_entries(select(.value | length > 0)));
  def run(event; argument): .hooks[event] = ((.hooks[event] // []) + [{hooks: [{type: "command", command: ($hook + " " + argument)}]}]);
  without_ours
  | if $action == "add" then
      run("Stop"; "wait") | run("Notification"; "wait")
      | run("UserPromptSubmit"; "clear") | run("PostToolUse"; "clear") | run("SessionEnd"; "clear")
    else . end
  | if .hooks == {} then del(.hooks) else . end
'

update() {
  local action=$1 temporary
  [ "$action" = add ] || [ -e "$SETTINGS" ] || return 0
  mkdir -p "$(dirname "$SETTINGS")"
  [ -e "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  temporary=$(mktemp "$SETTINGS.XXXXXX")
  if ! jq --arg action "$action" --arg hook "$HOOK" "$FILTER" "$SETTINGS" > "$temporary" 2>/dev/null; then
    rm -f "$temporary"
    echo "claude-hooks.sh: $SETTINGS isn't valid JSON, so it was left unchanged." >&2
    return 0
  fi
  chmod "$(stat -f %Lp "$SETTINGS")" "$temporary"
  mv "$temporary" "$SETTINGS"
}

case ${1:-} in
  add | remove) update "$1" ;;
  *)
    echo "usage: claude-hooks.sh add|remove" >&2
    exit 2
    ;;
esac
