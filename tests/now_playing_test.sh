#!/usr/bin/env bash
# Behavior of the bar item that shows the track playing in Music or Spotify.

source "$(dirname "$0")/lib.sh"

readonly PLUGIN=$REPO_DIR/sketchybar/.config/sketchybar/plugins/now_playing.sh

# pgrep finds a player when $SANDBOX/running-<name> exists. osascript answers a track
# question with $SANDBOX/track-<name>, which is empty while that player is paused.
stub_players() {
  cat > "$STUB_DIR/pgrep" <<STUB
#!/bin/sh
echo "pgrep \$*" >> "$CALL_LOG"
for last; do :; done
[ -e "$SANDBOX/running-\$last" ]
STUB
  cat > "$STUB_DIR/osascript" <<STUB
#!/bin/sh
echo "osascript \$*" >> "$CALL_LOG"
case "\$*" in
  *'"Music"'*current\ track*) cat "$SANDBOX/track-Music" 2>/dev/null ;;
  *'"Spotify"'*current\ track*) cat "$SANDBOX/track-Spotify" 2>/dev/null ;;
esac
exit 0
STUB
  chmod +x "$STUB_DIR/pgrep" "$STUB_DIR/osascript"
}

playing() {
  touch "$SANDBOX/running-$1"
  printf '%s' "$2" > "$SANDBOX/track-$1"
}

draw() {
  run_in_sandbox NAME=now_playing SENDER="${1:-now_playing_change}" SCROLL_DELTA="${2:-0}" "$PLUGIN"
}

shows_music_track() {
  stub_players
  playing Music 'Korn — A.D.I.D.A.S.'
  draw
  assert_called '^sketchybar --set now_playing drawing=on label=Korn — A\.D\.I\.D\.A\.S\.$'
}

shows_spotify_when_only_spotify_plays() {
  stub_players
  playing Music ''
  playing Spotify 'Tool — Schism'
  draw
  assert_called '^sketchybar --set now_playing drawing=on label=Tool — Schism$'
}

hides_when_nothing_plays() {
  stub_players
  playing Music ''
  draw
  assert_called '^sketchybar --set now_playing drawing=off$'
}

never_asks_closed_players() {
  stub_players
  draw
  assert_not_called '^osascript'
}

cuts_long_titles() {
  stub_players
  playing Music 'Godspeed You! Black Emperor — Storm (Lift Yr. Skinny Fists)'
  draw
  assert_called '^sketchybar --set now_playing drawing=on label=Godspeed You! Black Emperor — Storm \(Li…$'
}

toggles_on_click() {
  stub_players
  playing Music 'Korn — Freak on a Leash'
  draw mouse.clicked
  assert_called '^osascript -e tell application "Music" to playpause$'
}

skips_forward_on_scroll_up() {
  stub_players
  playing Spotify 'Tool — Schism'
  draw mouse.scrolled 3
  assert_called '^osascript -e tell application "Spotify" to next track$'
}

skips_back_on_scroll_down() {
  stub_players
  playing Spotify 'Tool — Schism'
  draw mouse.scrolled -3
  assert_called '^osascript -e tell application "Spotify" to previous track$'
}

run_case 'should show artist and title when Music is playing' shows_music_track
run_case "should show Spotify's track when only Spotify is playing" shows_spotify_when_only_spotify_plays
run_case 'should hide the item when nothing is playing' hides_when_nothing_plays
run_case 'should hide the item without asking when no player is running' never_asks_closed_players
run_case 'should cut a long title at 40 characters' cuts_long_titles
run_case 'should toggle play and pause when clicked' toggles_on_click
run_case 'should skip to the next track when scrolled up' skips_forward_on_scroll_up
run_case 'should go back a track when scrolled down' skips_back_on_scroll_down
finish
