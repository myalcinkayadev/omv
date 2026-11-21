#!/bin/sh
# The checks on your own open pull requests, read with gh every 5 minutes. Shows how many
# fail as a pill, or how many still run; hidden when every check passed or none ran. A pull
# request whose checks went from failing to passing gets a notice from Hammerspoon. A click
# opens the card. GH can point the tests at a stub.
# Keeps one line per pull request in the state file, "<state>\t<url>\t<repo>#<n>\t<title>",
# for the card and the next run. gh failing leaves it as it was, so a blip offline never
# turns a failing pull request into a passed one.

gh=${GH:-/opt/homebrew/bin/gh}
# Vantablack's colours, unless a theme was chosen in the system menu.
MUTED=0xff7a7a7a BLACK=0xff000000
# shellcheck disable=SC1091
[ -r "$HOME/.local/state/omv/theme/colors.sh" ] && . "$HOME/.local/state/omv/theme/colors.sh"
state_dir="$HOME/.local/state/omv"
state_file="$state_dir/github-ci"
passed_file="$state_dir/github-ci-passed"

if [ "${SENDER:-}" = mouse.clicked ]; then
  hs -c 'omvToggleCi()'
  exit 0
fi

hide() {
  sketchybar --set "$NAME" drawing=off
  sketchybar --trigger bar_fit
  exit 0
}

# shellcheck disable=SC2016
query='query { search(query: "is:pr is:open author:@me archived:false", type: ISSUE, first: 30) {
  nodes { ... on PullRequest { number title url repository { nameWithOwner }
    commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } } }'
filter='.data.search.nodes[] | select(.url) | [(.commits.nodes[0].commit.statusCheckRollup.state // "NONE"),
  .url, (.repository.nameWithOwner + "#" + (.number | tostring)), (.title | gsub("[\t\n]"; " "))] | @tsv'

[ -x "$gh" ] || hide
found=$("$gh" api graphql -f query="$query" --jq "$filter" 2>/dev/null) || hide

mkdir -p "$state_dir" 2>/dev/null
temporary=$(mktemp "$state_file.XXXXXX") || hide
printf '%s\n' "$found" | awk -F '\t' 'NF >= 3' > "$temporary"

# Pull requests that failed on the last run and pass now.
if [ -r "$state_file" ]; then
  awk -F '\t' 'NR == FNR { if ($1 == "FAILURE" || $1 == "ERROR") failed[$2] = 1; next }
    $1 == "SUCCESS" && failed[$2]' "$state_file" "$temporary" > "$passed_file.new"
  if [ -s "$passed_file.new" ]; then
    mv "$passed_file.new" "$passed_file"
    hs -c 'omvCiPassed()' >/dev/null 2>&1
  else
    rm -f "$passed_file.new"
  fi
fi
mv "$temporary" "$state_file"

failing=$(awk -F '\t' '$1 == "FAILURE" || $1 == "ERROR"' "$state_file" | wc -l | tr -d ' ')
running=$(awk -F '\t' '$1 == "PENDING" || $1 == "EXPECTED"' "$state_file" | wc -l | tr -d ' ')

if [ "$failing" -gt 0 ]; then
  sketchybar --set "$NAME" drawing=on icon=󰅙 "label=$failing" background.drawing=on \
    icon.color=$BLACK label.color=$BLACK
elif [ "$running" -gt 0 ]; then
  sketchybar --set "$NAME" drawing=on icon=󰔟 "label=$running" background.drawing=off \
    icon.color=$MUTED label.color=$MUTED
else
  hide
fi
# The label's width changes, so the right side may need to give way before the notch.
sketchybar --trigger bar_fit
