# AeroSpace reads one aerospace.toml and has no include, so omv builds it: its defaults from
# the repo with the user's ~/.config/omv/aerospace.toml applied (install/aerospace_merge.lua).
# Sourced, not run, after REPO_DIR is set.
# shellcheck disable=SC2034
readonly AEROSPACE_DEFAULTS=$REPO_DIR/config/aerospace/.config/aerospace/aerospace.toml
readonly AEROSPACE_USER=$HOME/.config/omv/aerospace.toml
readonly AEROSPACE_BUILT=$HOME/.config/aerospace/aerospace.toml
readonly AEROSPACE_HEADER="# Built by omv from its defaults and ~/.config/omv/aerospace.toml. Edit that file, then run omv reload."

# Prints the file omv would build now, or the user file's error on stderr and fails.
aerospace_build_text() {
  luajit "$REPO_DIR/install/aerospace_merge.lua" "$AEROSPACE_DEFAULTS" "$AEROSPACE_USER"
}

aerospace_built_by_omv() {
  [ "$(head -n 1 "$AEROSPACE_BUILT" 2>/dev/null)" = "$AEROSPACE_HEADER" ]
}

# Writes the built file. One omv didn't build is moved aside first, never deleted. A user
# file it can't read leaves the old built file and fails.
build_aerospace() {
  local folder temporary
  folder=$(dirname "$AEROSPACE_BUILT")
  mkdir -p "$folder"
  if [ -f "$AEROSPACE_BUILT" ] && ! aerospace_built_by_omv; then
    mv "$AEROSPACE_BUILT" "$AEROSPACE_BUILT.before-omv"
    echo "moved your aerospace.toml to aerospace.toml.before-omv; your settings now go in ~/.config/omv/aerospace.toml"
  fi
  temporary=$(mktemp "$folder/.aerospace.toml.XXXXXX")
  if ! aerospace_build_text > "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  mv "$temporary" "$AEROSPACE_BUILT"
}
