# Hammerspoon loads omv's config straight from the repo, through its MJConfigFile setting, so
# a new file in config/hammerspoon needs no link. Sourced, not run, after REPO_DIR is set.
# shellcheck disable=SC2034
readonly HAMMERSPOON_CONFIG=$REPO_DIR/config/hammerspoon/init.lua

hammerspoon_config() {
  # A key that isn't set reads as nothing, not as a failure that would stop the caller.
  defaults read org.hammerspoon.Hammerspoon MJConfigFile 2>/dev/null || true
}

# Hammerspoon reads the setting only when it starts, so a running one is restarted when the
# setting changes; one that isn't running is left for the user to open. A Hammerspoon that
# ignores the quit is force-quit after 5 seconds.
point_hammerspoon() {
  [ "$(hammerspoon_config)" = "$HAMMERSPOON_CONFIG" ] && return 0
  defaults write org.hammerspoon.Hammerspoon MJConfigFile "$HAMMERSPOON_CONFIG"
  local pid limit
  # pgrep fails when nothing matches; that's "not running", not an error.
  pid=$(pgrep -x Hammerspoon 2>/dev/null | head -n 1) || true
  [ -n "$pid" ] || return 0
  pkill -x Hammerspoon || true
  limit=$((SECONDS + 5))
  while kill -0 "$pid" 2>/dev/null && [ "$SECONDS" -lt "$limit" ]; do sleep 0.2; done
  if kill -0 "$pid" 2>/dev/null; then pkill -9 -x Hammerspoon; fi
  open -a Hammerspoon
}
