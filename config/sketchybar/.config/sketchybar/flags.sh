# Feature flags for shell scripts, read as Hammerspoon's flags.lua reads them: its defaults,
# then ~/.config/omv/flags, where the last "name=on" or "name=off" line wins and any other
# line is ignored. Sourced by sketchybarrc and bin/omv. OMV_FLAG_DEFAULTS names flags.lua;
# OMV_FLAGS_FILE, ~/.config/omv/flags unless set.

# Each flag and its default, "name true" or "name false", one a line.
omv_flag_names() {
  sed -n -E 's/^[[:space:]]*\["([a-z-]+)"\][[:space:]]*=[[:space:]]*(true|false).*/\1 \2/p' "$OMV_FLAG_DEFAULTS" 2>/dev/null
}

# on or off, for a flag and its default.
omv_flag_value() {
  local name=$1 default=$2 line
  line=$(grep -E "^[[:space:]]*$name[[:space:]]*=[[:space:]]*(on|off)[[:space:]]*$" "${OMV_FLAGS_FILE:-$HOME/.config/omv/flags}" 2>/dev/null | tail -n 1 || true)
  case $(echo "${line#*=}" | tr -d '[:space:]') in
    on) echo on ;;
    off) echo off ;;
    *) [ "$default" = true ] && echo on || echo off ;;
  esac
}

# Exits 0 when the flag is on; an unknown flag is off.
omv_flag_on() {
  local default
  default=$(omv_flag_names | awk -v name="$1" '$1 == name { print $2 }')
  [ -n "$default" ] && [ "$(omv_flag_value "$1" "$default")" = on ]
}
