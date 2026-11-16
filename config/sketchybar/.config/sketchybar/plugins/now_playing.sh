#!/bin/sh
# Shows the track playing in Music or Spotify, hidden while nothing plays.
# Click to play or pause, right-click for the lyrics window, scroll up or down for the
# next or previous track.
# Only asks a player that is already running, so it never launches one.
# Hammerspoon sends now_playing_change when either player changes track or state.

max_characters=40

if [ "${SENDER:-}" = mouse.clicked ] && [ "${BUTTON:-}" = right ]; then
  hs -c 'omvToggleLyrics()'
  exit 0
fi

# Prints "Artist — Title" while the player is playing, nothing otherwise.
track_of() {
  osascript -e "tell application \"$1\" to if player state is playing then return (artist of current track) & \" — \" & (name of current track)" 2>/dev/null
}

playing_player=
track=
for player in Music Spotify; do
  pgrep -x "$player" >/dev/null || continue
  track=$(track_of "$player")
  if [ -n "$track" ]; then
    playing_player=$player
    break
  fi
done

if [ -n "$playing_player" ]; then
  case "${SENDER:-}" in
    mouse.clicked)
      osascript -e "tell application \"$playing_player\" to playpause"
      ;;
    mouse.scrolled)
      case ${SCROLL_DELTA:-0} in
        0 | 0.0* | -0 | -0.0*) ;;
        -*) osascript -e "tell application \"$playing_player\" to previous track" ;;
        *) osascript -e "tell application \"$playing_player\" to next track" ;;
      esac
      ;;
  esac
fi

if [ -z "$playing_player" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

# Perl counts characters, not bytes, so a cut never splits an accented letter.
label=$(printf '%s' "$track" | perl -CSA -Mutf8 -ne "print length > $max_characters ? substr(\$_, 0, $max_characters - 1) . '…' : \$_")
sketchybar --set "$NAME" drawing=on "label=$label"
