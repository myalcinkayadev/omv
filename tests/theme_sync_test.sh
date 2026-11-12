#!/usr/bin/env bash
# Behavior of theme-sync.sh, which downloads Omarchy's theme colours. curl is a stub that
# answers the theme list and each colors.toml, or fails as if offline.

source "$(dirname "$0")/lib.sh"

readonly SCRIPT=$REPO_DIR/hammerspoon/.hammerspoon/theme-sync.sh

themes_dir() {
  echo "$HOME_DIR/.local/share/omv/themes"
}

# The list holds two themes, a file, and a name that could be a path.
stub_github() {
  cat > "$STUB_DIR/curl" <<'STUB'
#!/bin/sh
echo "curl $*" >> "$CALL_LOG"
case "$*" in
  *api.github.com/repos/omacom/omarchy) echo '{"default_branch":"quattro"}' ;;
  *api.github.com*) echo '[{"name":"nord","type":"dir"},{"name":"tokyo-night","type":"dir"},{"name":"README.md","type":"file"},{"name":"..%2Fx","type":"dir"}]' ;;
  *raw.githubusercontent.com/omacom/omarchy/quattro/themes/*/colors.toml*)
    out=$(printf '%s\n' "$@" | sed -n '/^-o$/{n;p;}')
    printf 'accent = "#123456"\n' > "$out"
    ;;
esac
STUB
  chmod +x "$STUB_DIR/curl"
}

run_sync() {
  run_in_sandbox PATH="$STUB_DIR:/usr/bin:/bin:/opt/homebrew/bin" "$SCRIPT"
}

downloads_each_theme() {
  stub_github
  run_sync >/dev/null
  [ -f "$(themes_dir)/nord/colors.toml" ] && [ -f "$(themes_dir)/tokyo-night/colors.toml" ] || fail "$(ls -R "$(themes_dir)" 2>&1)"
}

skips_entries_that_arent_themes() {
  stub_github
  run_sync >/dev/null
  [ "$(ls "$(themes_dir)" | tr '\n' ' ')" = 'nord tokyo-night ' ] || fail "got: $(ls "$(themes_dir)")"
}

says_how_many() {
  stub_github
  [ "$(run_sync)" = 2 ] || fail "printed: $(run_sync)"
}

keeps_themes_when_offline() {
  mkdir -p "$(themes_dir)/nord"
  printf 'accent = "#abcdef"\n' > "$(themes_dir)/nord/colors.toml"
  stub curl 6
  run_sync >/dev/null 2>&1 || true
  [ "$(cat "$(themes_dir)/nord/colors.toml")" = 'accent = "#abcdef"' ] || fail 'a theme was lost while offline'
}

fails_when_offline() {
  stub curl 6
  assert_exit_nonzero run_sync
}

run_case "should download each theme's colours" downloads_each_theme
run_case "should skip entries that aren't themes" skips_entries_that_arent_themes
run_case 'should print how many themes it got' says_how_many
run_case 'should keep the themes it has when offline' keeps_themes_when_offline
run_case 'should exit non-zero when offline' fails_when_offline
finish
