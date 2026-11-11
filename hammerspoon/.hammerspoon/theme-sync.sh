#!/bin/sh
# Usage: theme-sync.sh
# Downloads the colours of Omarchy's themes (github.com/basecamp/omarchy, MIT) into
# ~/.local/share/omv/themes/<name>/colors.toml, for the theme picker, and prints how many
# it got. Only the colours are fetched, and only when asked. Offline, the themes already
# there stay as they are.

PATH="$PATH:/opt/homebrew/bin"
themes="$HOME/.local/share/omv/themes"
api="https://api.github.com/repos/basecamp/omarchy"

# The default branch is named after each release, so it's looked up, not assumed.
branch=$(curl -fsS "$api" | jq -r '.default_branch // empty') || branch=
names=$(curl -fsS "$api/contents/themes" | jq -r '.[] | select(.type == "dir") | .name') || names=
if [ -z "$branch" ] || [ -z "$names" ]; then
  echo "Couldn't reach GitHub" >&2
  exit 1
fi

count=0
for name in $names; do
  # A name becomes a folder, so anything that could be a path is skipped.
  case $name in
    '' | *[!a-z0-9-]*) continue ;;
  esac
  temporary=$(mktemp)
  if curl -fsS "https://raw.githubusercontent.com/basecamp/omarchy/$branch/themes/$name/colors.toml" -o "$temporary"; then
    mkdir -p "$themes/$name"
    mv "$temporary" "$themes/$name/colors.toml"
    count=$((count + 1))
  else
    rm -f "$temporary"
  fi
done
echo "$count"
