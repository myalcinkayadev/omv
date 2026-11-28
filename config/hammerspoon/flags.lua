-- Feature flags: each of omv's features can be turned off, and a few start off. The
-- defaults are here, in the repo; ~/.config/omv/flags turns them on or off on this Mac, one
-- "name=on" or "name=off" per line, with # for comments. Lines that aren't one of those, or
-- name an unknown flag, are ignored. A feature that's off isn't loaded: its key is free, its
-- card and bar item are gone, and nothing of it runs in the background. The desktop itself
-- (tiling, the palette, the key list, the system menu, themes and the clock) has no flag.
-- Read when Hammerspoon loads, so a change takes a reload; `omv flags <name> on|off` reloads.
-- The bar and Ghostty read the same file through flags.sh, which reads the defaults below.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local flags = {}

flags.PATH = (os.getenv("HOME") or "") .. "/.config/omv/flags"

flags.DEFAULTS = {
  -- Cards and their bar items.
  ["weather"] = true, -- the temperature in the bar and the forecast card (Option+Shift+O)
  ["battery"] = true, -- the battery item and card (Option+Shift+B)
  ["bluetooth"] = true, -- the Bluetooth item and card (Option+Shift+Y)
  ["network"] = true, -- the Wi-Fi and Ethernet items and cards (Option+Shift+W, Option+Shift+E)
  ["sound"] = true, -- the volume item, the Sound card (Option+Shift+V) and the next output (Option+O)
  ["calendar"] = true, -- the calendar on a click of the clock, the next meeting, and joining it (Option+Shift+C)
  ["disk"] = true, -- the low-disk item and the Disk card (Option+Shift+X)
  ["tailscale"] = true, -- the Tailscale item and card
  ["focus"] = true, -- the Do Not Disturb item and its switch in the system menu
  -- Tools.
  ["clipboard"] = true, -- clipboard history (Option+V) and its paused item
  ["snippets"] = true, -- your snippets in the palette
  ["calculator"] = true, -- sums and conversions in the palette
  ["clipboard-actions"] = true, -- JSON, JWT, base64, URL escapes and epoch times from the clipboard, in the palette
  ["translate"] = true, -- translating the selection (Option+Y)
  ["capture"] = true, -- the capture menu (Option+Shift+S) and the recording item
  ["reminders"] = true, -- reminders and Pomodoro (Option+Shift+M) and their item
  ["daily-note"] = true, -- the quick note (Option+Shift+D)
  ["airdrop"] = true, -- sharing with AirDrop (Option+Shift+Q)
  ["copy-url"] = true, -- copying the browser's URL (Option+Shift+U)
  ["keep-awake"] = true, -- keeping the Mac awake (Option+Shift+I) and its item
  ["night-light"] = true, -- night light (Option+Shift+Z), its item and its switch in the system menu
  ["mic-mute"] = true, -- muting the mic (Option+M) and its item
  ["window-sizing"] = true, -- halves, thirds, almost full and centred for the focused window (Ctrl+Option+arrows, C)
  ["volume-popups"] = true, -- omv's volume and brightness pop-ups, and dimming an external display
  ["processes"] = true, -- hungry processes and ports (Option+Shift+P)
  ["lyrics"] = true, -- the lyrics window
  ["now-playing"] = true, -- the playing track in the bar
  -- For developers.
  ["claude"] = true, -- Claude Code's usage, the waiting pill and the Agents card (Option+Shift+A)
  ["send-to-agent"] = true, -- sending the selection or a screenshot to a waiting agent (Option+P)
  ["away-digest"] = true, -- what your agents did while the screen was locked, shown when you unlock it
  ["github-prs"] = true, -- pull requests waiting for your review (Option+Shift+G) and their item
  ["github-ci"] = true, -- the checks on your own open pull requests, their item and the passed notices
  ["dev-layout"] = true, -- the dev layout and the agent grid
  ["drop-down-terminal"] = true, -- Ghostty's quick terminal (Option+`)
  ["long-command-notices"] = true, -- Ghostty's notice when a long command finishes
  -- Off unless turned on.
  ["meeting-mode"] = false, -- Do Not Disturb, paused music and hidden chat apps while a meeting runs
  ["file-search"] = false, -- the palette also lists recent files matching what's typed (mdfind)
  ["browser-tabs"] = false, -- the palette also lists the browser's open tabs (AppleScript)
  ["stalls"] = false, -- logs each time Hammerspoon stalls to ~/.local/state/omv/stalls.log
  ["dictation"] = false, -- hold Right Option to talk, release to type it, heard on the Mac
  ["voice-agents"] = false, -- hold Right Command, say "tell omv …" or "reply …" for an agent's prompt; needs dictation, claude and send-to-agent
  ["brew-outdated"] = false, -- outdated Homebrew packages in the bar, and brew upgrade on a click
  ["system-load"] = false, -- CPU and memory in the bar, only while the Mac is busy
  ["input-source"] = false, -- the keyboard input source in the bar, as TR or US; a click switches it
  ["world-clocks"] = false, -- the times in ~/.config/omv/clocks, under the calendar card's events
  ["in-use"] = false, -- a green camera and an orange mic in the bar while another app uses them
}

-- text is the flags file's contents, or nil when there's none.
function flags.read(text)
  local found = {}
  for name, value in pairs(flags.DEFAULTS) do found[name] = value end
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local name, value = line:match("^%s*([%w%-]+)%s*=%s*(%a+)%s*$")
    if name and found[name] ~= nil and (value == "on" or value == "off") then found[name] = value == "on" end
  end
  return found
end

return flags
