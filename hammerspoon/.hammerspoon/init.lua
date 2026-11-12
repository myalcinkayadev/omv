-- App-launch keys, the system menu, the key list and the calendar. AeroSpace owns every
-- window key; see README.md for the full map.
-- hs.hotkey needs no Accessibility permission, so none is granted.
-- Each card lives in features/, sharing the floating card from shell.lua. This file only
-- loads them, in the order they start, and binds every key in one place.
require("hs.ipc")

hs.menuIcon(false)
hs.dockIcon(false)
hs.uploadCrashData(false)
-- Hotkeys log every enable and disable, which would add lines each time a card opens.
hs.hotkey.setLogLevel("warning")

local shell = require("shell")
local systemMenu = require("features.menu")
local keys = require("features.keys")
local windowList = require("features.windows")
local pullRequests = require("features.prs")
local captureMenu = require("features.capture")
local reminderCards = require("features.reminders")
local calendarCard = require("features.calendar")
local networkCards = require("features.network")
local soundCard = require("features.sound")
local weatherCard = require("features.weather")
local batteryCard = require("features.battery")
local agentsCard = require("features.agents")
local waitingClaude = require("features.waiting")
local quickNote = require("features.note")
local clipboardHistory = require("features.clipboard")
local bluetoothCard = require("features.bluetooth")
-- Loaded now, not only from the system menu, so the chosen theme colours the cards from the start.
require("features.theme")
local hungryProcesses = require("features.procs")
local diskCard = require("features.disk")
local lyricsWindow = require("features.lyrics")
require("features.osd")
local focusMode = require("features.focus")
local tailscalePanel = require("features.tailscale")
local nightLight = require("features.nightshift")
local devLayout = require("features.devlayout")
local airDrop = require("features.share")

local SUPER = { "alt" }
local SUPER_SHIFT = { "alt", "shift" }
local COPY_URL = hs.configdir .. "/copy-url.sh"
local run, open = shell.run, shell.open
-- The browser and editor the keys open, from ~/.config/omv/apps, read when this config loads.
local chosen = require("apps").read(shell.readText(require("apps").PATH))

-- Each key keeps its action, so the key list can run it too. The group is the key list
-- section it shows under.
local function bindKey(modifiers, key, label, description, group, action)
  hs.hotkey.bind(modifiers, key, action)
  keys.launchers[#keys.launchers + 1] = { label = label, description = description, group = group, run = action, runs = true }
end

local function openOnWorkspace(workspace, arguments)
  return run(shell.LAUNCH, { workspace, "/usr/bin/open", table.unpack(arguments) })
end

-- Copy URL (Option+Shift+U)
local function copyUrl()
  hs.task.new(COPY_URL, function(code, _, errors)
    local message = code == 0 and "Copied URL" or (errors:gsub("%s+$", ""))
    shell.alert(message, 1.2)
  end):start()
end

bindKey(SUPER_SHIFT, "return", "Option+Shift+Enter", "New " .. chosen.browser .. " window", "Apps", openOnWorkspace("3", { "-na", chosen.browser, "--args", "--new-window" }))
bindKey(SUPER_SHIFT, "n", "Option+Shift+N", "Open " .. chosen.editor, "Apps", openOnWorkspace("2", { "-a", chosen.editor }))
bindKey(SUPER_SHIFT, "f", "Option+Shift+F", "Finder at home", "Apps", open({ shell.HOME }))
-- No key: it's run from the palette or the key list.
keys.launchers[#keys.launchers + 1] = { description = "Dev layout: " .. chosen.editor .. ", Claude Code and a shell",
  group = "Apps", run = function() devLayout.open(chosen.editor) end, runs = true }
bindKey(SUPER_SHIFT, "t", "Option+Shift+T", "btop", "Apps", run(shell.LAUNCH, { "1", shell.GHOSTTY_WINDOW, "/opt/homebrew/bin/btop" }))
bindKey(SUPER_SHIFT, "i", "Option+Shift+I", "Keep the Mac awake, or stop", "Tools", run(shell.SKETCHYBAR, { "--trigger", "keep_awake_toggle" }))
bindKey(SUPER_SHIFT, "u", "Option+Shift+U", "Copy " .. chosen.browser .. "'s current URL", "Tools", copyUrl)
bindKey(SUPER_SHIFT, "s", "Option+Shift+S", "Capture the screen", "Tools", captureMenu.toggle)
bindKey(SUPER_SHIFT, "m", "Option+Shift+M", "Set a reminder", "Tools", reminderCards.new)
bindKey(SUPER_SHIFT, "d", "Option+Shift+D", "Note in today's daily note", "Tools", quickNote.toggle)
bindKey(SUPER_SHIFT, "g", "Option+Shift+G", "PRs waiting for your review", "Tools", pullRequests.toggle)
bindKey(SUPER_SHIFT, "p", "Option+Shift+P", "Hungry processes and ports", "Tools", hungryProcesses.toggle)
bindKey(SUPER_SHIFT, "x", "Option+Shift+X", "Disk space and cleanup", "Tools", diskCard.toggle)
bindKey(SUPER_SHIFT, "z", "Option+Shift+Z", "Night light on or off", "Tools", nightLight.toggle)
bindKey(SUPER_SHIFT, "q", "Option+Shift+Q", "Share with AirDrop", "Tools", airDrop.share)
bindKey(SUPER_SHIFT, "a", "Option+Shift+A", "Claude session waiting for you", "Tools", waitingClaude.focus)
bindKey(SUPER_SHIFT, "c", "Option+Shift+C", "Join the meeting starting now", "Tools", calendarCard.join)
bindKey(SUPER_SHIFT, "space", "Option+Shift+Space", "Show or hide the bar", "Cards", run(shell.SKETCHYBAR, { "--bar", "hidden=toggle" }))
bindKey(SUPER_SHIFT, "w", "Option+Shift+W", "Wi-Fi", "Cards", networkCards.toggleWifi)
bindKey(SUPER_SHIFT, "y", "Option+Shift+Y", "Bluetooth", "Cards", bluetoothCard.toggle)
bindKey(SUPER_SHIFT, "e", "Option+Shift+E", "Ethernet", "Cards", networkCards.toggleEthernet)
bindKey(SUPER_SHIFT, "v", "Option+Shift+V", "Sound", "Cards", soundCard.toggle)
bindKey(SUPER_SHIFT, "o", "Option+Shift+O", "Weather", "Cards", weatherCard.toggle)
bindKey(SUPER_SHIFT, "b", "Option+Shift+B", "Battery", "Cards", batteryCard.toggle)
bindKey(SUPER, "escape", "Option+Escape", "System menu", "Cards", systemMenu.toggle)
bindKey(SUPER, "space", "Option+Space", "Windows, apps and commands", "Cards", windowList.toggle)
bindKey(SUPER, "v", "Option+V", "Clipboard history", "Cards", clipboardHistory.toggle)

-- Now playing: Music and Spotify announce every track and play-state change, so the bar
-- and the lyrics window update only then. Global, so the watchers are never garbage-collected.
local redrawBarTrack = run(shell.SKETCHYBAR, { "--trigger", "now_playing_change" })
local function playerChanged()
  redrawBarTrack()
  lyricsWindow.playerChanged()
end
omvMediaWatchers = {
  hs.distributednotifications.new(playerChanged, "com.apple.Music.playerInfo"):start(),
  hs.distributednotifications.new(playerChanged, "com.spotify.client.PlaybackStateChanged"):start(),
}

-- Ghostty owns this key, so it is listed here rather than bound.
keys.launchers[#keys.launchers + 1] = { label = "Option+`", description = "Drop-down terminal", group = "Apps" }

-- 44 is the physical "/" key, so this stays the same key on the Turkish layout.
bindKey(SUPER, 44, "Option+/", "Show or hide this list", "Cards", keys.toggle)
-- Running it from the list would only open the list again.
keys.launchers[#keys.launchers].runs = false

-- Scripts open the cards with hs -c, for example the bar's clock: hs -c 'omvToggleCalendar()'.
-- Each call waits for the next run-loop turn, because drawing a card inside the hs -c
-- request makes that request call back into itself.
local function later(fn)
  return function() hs.timer.doAfter(0, fn) end
end

omvToggleSystemMenu = later(systemMenu.toggle)
omvToggleSound = later(soundCard.toggle)
omvToggleWifi = later(networkCards.toggleWifi)
omvToggleBluetooth = later(bluetoothCard.toggle)
-- Answers at once, not later: the bar's plugin reads the answer.
omvBluetoothPower = bluetoothCard.power
omvToggleEthernet = later(networkCards.toggleEthernet)
omvToggleWeather = later(weatherCard.toggle)
omvToggleBattery = later(batteryCard.toggle)
omvToggleAgents = later(agentsCard.toggle)
omvToggleLyrics = later(lyricsWindow.toggle)
omvStopRecording = later(captureMenu.stopRecording)
omvToggleFocus = later(focusMode.toggle)
omvToggleTailscale = later(tailscalePanel.toggle)
omvToggleNightLight = later(nightLight.toggle)

-- SketchyBar's config calls this when it starts: a restarted bar has lost the items set
-- here, and they are only sent again when they change.
omvRedrawBar = later(function()
  weatherCard.redrawBar()
  calendarCard.redrawBar()
  reminderCards.redrawBar()
  clipboardHistory.redrawBar()
end)
omvToggleKeyList = later(keys.toggle)
omvToggleCalendar = later(calendarCard.toggle)
omvJoinMeeting = later(calendarCard.join)
omvToggleWindows = later(windowList.toggle)
omvTogglePrs = later(pullRequests.toggle)
omvToggleClipboard = later(clipboardHistory.toggle)
omvResumeClipboard = later(clipboardHistory.resume)
omvToggleProcesses = later(hungryProcesses.toggle)
omvToggleDisk = later(diskCard.toggle)
omvFocusClaude = later(waitingClaude.focus)
omvToggleCapture = later(captureMenu.toggle)
omvToggleReminders = later(reminderCards.toggle)
omvNewReminder = later(reminderCards.new)
