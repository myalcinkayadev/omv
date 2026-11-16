#!/usr/bin/env bash
# The move to the new layout: the Stow packages now live in config/ and agents/, and
# Hammerspoon loads from config/hammerspoon. This removes the links into the old package
# folders, which the pull left pointing at nothing, so Stow can link the new ones. Every other
# link and every real file stays. Safe on a fresh setup and safe to run twice.

set -euo pipefail

CLONE=$(cd "$(dirname "$0")/.." && pwd -P)
readonly CLONE
readonly OLD_PACKAGES=(aerospace sketchybar claude swipeaerospace ghostty nvim btop hammerspoon opencode pi)

# $1 with "." and ".." collapsed, segment by segment, without touching the disk. Globbing is
# off, so a segment such as omv[1] stays as written.
collapse() {
  local part parts=() IFS=/
  set -f
  for part in $1; do
    case $part in
      '' | .) ;;
      ..) if [ "${#parts[@]}" -gt 0 ]; then unset 'parts[${#parts[@]}-1]'; fi ;;
      *) parts+=("$part") ;;
    esac
  done
  set +f
  printf '/%s' "${parts[@]+"${parts[@]}"}"
}

# $1 with its longest existing folder resolved physically, so /var and /private/var, or a
# home reached through a link, compare equal. The rest needn't exist.
physical() {
  local folder=$1 rest=''
  while [ ! -d "$folder" ]; do
    rest=/${folder##*/}$rest
    folder=${folder%/*}
    [ -n "$folder" ] || folder=/
  done
  echo "$(cd "$folder" && pwd -P)$rest"
}

# The path the link $1 names, whether or not it exists.
target_of() {
  local text folder
  text=$(readlink "$1")
  folder=$(cd "$(dirname "$1")" && pwd -P)
  [[ $text == /* ]] || text=$folder/$text
  physical "$(collapse "$text")"
}

into_old_package() {
  local target=$1 package
  for package in "${OLD_PACKAGES[@]}"; do
    [[ $target == "$CLONE/$package" || $target == "$CLONE/$package/"* ]] && return 0
  done
  return 1
}

# Where omv's links live, each with how deep to look; find doesn't follow links.
omv_links() {
  local place depth
  while read -r place depth; do
    [ -d "$HOME/$place" ] || continue
    find "$HOME/$place" -maxdepth "$depth" -type l
  done <<'EOF'
.hammerspoon 2
.config 4
.claude 1
.pi/agent/extensions 1
EOF
}

while IFS= read -r link; do
  into_old_package "$(target_of "$link")" || continue
  rm "$link"
  echo "removed ${link#"$HOME/"}"
done < <(omv_links)
