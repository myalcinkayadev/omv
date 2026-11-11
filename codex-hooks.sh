#!/usr/bin/env bash
# Usage: codex-hooks.sh add|remove
# Adds or removes the hooks in ~/.codex/hooks.json that tell the bar when a Codex session
# works, asks for approval or is done. They run the same claude-waiting.sh as Claude's,
# naming the agent codex. The file is yours: only entries that run claude-waiting.sh are
# touched, so other hooks, such as herdr's, stay, and a file jq can't read is left unchanged.

set -euo pipefail

readonly HOOKS=$HOME/.codex/hooks.json
readonly HOOK='$HOME/.claude/claude-waiting.sh wait codex'

# Entries are matched by the script's name, so an older form of the line is replaced too.
readonly FILTER='
  def ours: any(.hooks[]?; .command | tostring | contains("claude-waiting.sh"));
  def without_ours: .hooks |= ((. // {}) | with_entries(.value |= map(select(ours | not))) | with_entries(select(.value | length > 0)));
  def run(event): .hooks[event] = ((.hooks[event] // []) + [{hooks: [{type: "command", command: $hook}]}]);
  without_ours
  | if $action == "add" then run("UserPromptSubmit") | run("PostToolUse") | run("PermissionRequest") | run("Stop") else . end
  | if .hooks == {} then del(.hooks) else . end
'

update() {
  local action=$1 temporary
  [ "$action" = add ] || [ -e "$HOOKS" ] || return 0
  mkdir -p "$(dirname "$HOOKS")"
  [ -e "$HOOKS" ] || echo '{}' > "$HOOKS"
  temporary=$(mktemp "$HOOKS.XXXXXX")
  if ! jq --arg action "$action" --arg hook "$HOOK" "$FILTER" "$HOOKS" > "$temporary" 2>/dev/null; then
    rm -f "$temporary"
    echo "codex-hooks.sh: $HOOKS isn't valid JSON, so it was left unchanged." >&2
    return 0
  fi
  chmod "$(stat -f %Lp "$HOOKS")" "$temporary"
  mv "$temporary" "$HOOKS"
}

case ${1:-} in
  add | remove) update "$1" ;;
  *)
    echo "usage: codex-hooks.sh add|remove" >&2
    exit 2
    ;;
esac
