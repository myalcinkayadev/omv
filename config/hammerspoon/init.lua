-- App-launch keys, the system menu, the key list and the calendar. AeroSpace owns every
-- window key; see README.md for the full map.
-- hs.hotkey needs no Accessibility permission, so none is granted.
-- Each card lives in features/, sharing the floating card from shell.lua. This file only
-- loads them, in the order they start, and binds every key in one place.
-- Hammerspoon loads this config from the repo, so its own ~/.hammerspoon is no longer the
-- config folder; its Spoons still load from there.
package.path = package.path .. ";" .. (os.getenv("HOME") or "") .. "/.hammerspoon/Spoons/?.spoon/init.lua"
require("hs.ipc")
-- A timed-out hs command would otherwise make every print after it recurse; see ipcguard.lua.
print = require("ipcguard").wrap(hs.ipc, print)
-- When this config loaded, so omv update can tell a finished reload from the old instance.
omvLoadedAt = hs.timer.secondsSinceEpoch()
-- Installs the hs command when it's missing, as on a fresh Mac: the bar and doctor.sh need it.
local hsPrefix = require("hscli").prefix(hs.fs.attributes("/opt/homebrew") ~= nil)
local hsStatus = hs.ipc.cliStatus(hsPrefix, true)
if require("hscli").needsInstall(hsStatus, hs.fs.attributes(hsPrefix .. "/bin/hs") ~= nil) then
  -- A link that leads nowhere has to go before a new one can be made.
  if hsStatus == "broken" then hs.ipc.cliUninstall(hsPrefix, true) end
  hs.ipc.cliInstall(hsPrefix, true)
end

hs.menuIcon(false)
hs.dockIcon(false)
hs.uploadCrashData(false)
-- Hotkeys log every enable and disable, which would add lines each time a card opens.
hs.hotkey.setLogLevel("warning")

local shell = require("shell")
local flags = require("flags")
-- Read once: a change to ~/.config/omv/flags takes a reload, which `omv flags` does.
local enabled = flags.read(shell.readText(flags.PATH))

-- A feature's module when its flag is on, else nil: then none of it loads, so its key stays
-- free, its card is gone, and nothing of it runs in the background.
local function feature(flag, module)
  if enabled[flag] then return require(module) end
  return nil
end

-- The desktop itself, which no flag turns off.
local systemMenu = require("features.menu")
local keys = require("features.keys")
local windowList = require("features.windows")
-- Puts each workspace on its screen for the screens plugged in, its apps on it, and its card.
local workspaceCards = require("features.workspaces")
-- Loaded now, not only from the system menu, so the chosen theme colours the cards from the start.
local themes = require("features.theme")
-- Loaded now, so the Permissions card can open on its own the first time omv loads.
require("features.permissions")
-- Starts the bar again when it has gone, since nothing else would.
require("features.barwatch")

local pullRequests = feature("github-prs", "features.prs")
local checks = feature("github-ci", "features.ci")
local captureMenu = feature("capture", "features.capture")
local reminderCards = feature("reminders", "features.reminders")
local calendarCard = feature("calendar", "features.calendar")
-- World clocks live in the calendar card, so they need it.
if calendarCard then calendarCard.withClocks = enabled["world-clocks"] end
-- Reads the calendar's meetings, so it loads only with it.
local meetingMode = calendarCard and feature("meeting-mode", "features.meeting")
if meetingMode then
  meetingMode.setup(calendarCard)
  calendarCard.onJoin = meetingMode.joined
end
local networkCards = feature("network", "features.network")
local soundCard = feature("sound", "features.sound")
local weatherCard = feature("weather", "features.weather")
local batteryCard = feature("battery", "features.battery")
local agentsCard = feature("claude", "features.agents")
local waitingClaude = feature("claude", "features.waiting")
-- Paste into, and read, the sessions the waiting feature finds, so they load only with it.
local sendToAgent = waitingClaude and feature("send-to-agent", "features.sendto")
if waitingClaude then feature("away-digest", "features.digest") end
local talkBack = waitingClaude and feature("talk-back", "features.talkback")
local quickNote = feature("daily-note", "features.note")
local clipboardHistory = feature("clipboard", "features.clipboard")
local bluetoothCard = feature("bluetooth", "features.bluetooth")
local hungryProcesses = feature("processes", "features.procs")
local diskCard = feature("disk", "features.disk")
local lyricsWindow = feature("lyrics", "features.lyrics")
feature("volume-popups", "features.osd")
local focusMode = feature("focus", "features.focus")
local tailscalePanel = feature("tailscale", "features.tailscale")
local nightLight = feature("night-light", "features.nightshift")
local mic = feature("mic-mute", "features.micmute")
local inUseDots = feature("in-use", "features.inuse")
local devLayout = feature("dev-layout", "features.devlayout")
local airDrop = feature("airdrop", "features.share")
local translateSelection = feature("translate", "features.translate")
feature("stalls", "features.stalls")
local dictationKey = feature("dictation", "features.dictation")
if dictationKey and sendToAgent and enabled["voice-agents"] then
  dictationKey.agents({ rows = waitingClaude.rows, deliver = sendToAgent.deliver, spoke = talkBack and talkBack.spoke })
end
if dictationKey and talkBack then
  dictationKey.onPress(talkBack.stop)
  talkBack.whileRecording(dictationKey.recording)
end
local windowSizing = feature("window-sizing", "features.windowsize")
local inputSource = feature("input-source", "features.inputsource")

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

-- Opens app with open's arguments on the workspace ~/.config/omv/workspaces keeps it on, read
-- when the key is pressed, or on the one you're on.
local function openOnWorkspace(app, arguments)
  return function()
    run(shell.LAUNCH, { workspaceCards.homeOf(app), "/usr/bin/open", table.unpack(arguments) })()
  end
end

-- Copy URL (Option+Shift+U)
local function copyUrl()
  hs.task.new(COPY_URL, function(code, _, errors)
    local message = code == 0 and "Copied URL" or (errors:gsub("%s+$", ""))
    shell.alert(message, 1.2)
  end):start()
end

bindKey(SUPER_SHIFT, "return", "Option+Shift+Enter", "New " .. chosen.browser .. " window", "Apps", openOnWorkspace(chosen.browser, { "-na", chosen.browser, "--args", "--new-window" }))
bindKey(SUPER_SHIFT, "n", "Option+Shift+N", "Open " .. chosen.editor, "Apps", openOnWorkspace(chosen.editor, { "-a", chosen.editor }))
bindKey(SUPER_SHIFT, "f", "Option+Shift+F", "Finder at home", "Apps", open({ shell.HOME }))
if devLayout then
  -- No key: it's run from the palette or the key list.
  keys.launchers[#keys.launchers + 1] = { description = "Dev layout: " .. chosen.editor .. ", Claude Code and a shell",
    group = "Apps", run = function() devLayout.open(chosen.editor) end, runs = true }
  keys.launchers[#keys.launchers + 1] = { description = "Agent grid: 2–4 Claude agents in worktrees",
    group = "Apps", run = devLayout.openGrid, runs = true }
end
bindKey(SUPER, "w", "Option+W", "This window: keep its app on this workspace, or move it", "Windows", workspaceCards.window)
if windowSizing then
  for _, sizing in ipairs({
    { "left", "Ctrl+Option+←", "Left half, then a third, then two-thirds" },
    { "right", "Ctrl+Option+→", "Right half, then a third, then two-thirds" },
    { "up", "Ctrl+Option+↑", "Almost full" },
    { "down", "Ctrl+Option+↓", "Centred at two-thirds" },
    { "c", "Ctrl+Option+C", "Centre the window" },
  }) do
    local action = sizing[1] == "c" and "center" or sizing[1]
    bindKey({ "ctrl", "alt" }, sizing[1], sizing[2], sizing[3], "Windows", function() windowSizing.size(action) end)
  end
end
-- No key: it's run from the palette, the key list or the system menu.
keys.launchers[#keys.launchers + 1] = { description = "Workspaces and screens", group = "Tools", run = workspaceCards.open, runs = true }
if dictationKey then
  keys.launchers[#keys.launchers + 1] = { label = "Right Option", description = "Dictate: hold to talk, tap twice for hands-free",
    group = "Tools", run = dictationKey.open, runs = true }
  keys.launchers[#keys.launchers + 1] = { description = "Paste last dictation", group = "Tools", run = dictationKey.pasteLast, runs = true }
end
if meetingMode then
  -- No key: it's run from the palette or the key list.
  keys.launchers[#keys.launchers + 1] = { description = "Meeting mode on or off",
    group = "Tools", run = meetingMode.toggle, runs = true }
end
bindKey(SUPER_SHIFT, "t", "Option+Shift+T", "btop", "Apps", function()
  run(shell.LAUNCH, { workspaceCards.homeOf("Ghostty"), shell.GHOSTTY_WINDOW, "/opt/homebrew/bin/btop" })()
end)
if enabled["keep-awake"] then
  bindKey(SUPER_SHIFT, "i", "Option+Shift+I", "Keep the Mac awake, or stop", "Tools", run(shell.SKETCHYBAR, { "--trigger", "keep_awake_toggle" }))
end
if enabled["copy-url"] then
  bindKey(SUPER_SHIFT, "u", "Option+Shift+U", "Copy " .. chosen.browser .. "'s current URL", "Tools", copyUrl)
end
if captureMenu then bindKey(SUPER_SHIFT, "s", "Option+Shift+S", "Capture the screen", "Tools", captureMenu.toggle) end
if reminderCards then bindKey(SUPER_SHIFT, "m", "Option+Shift+M", "Set a reminder", "Tools", reminderCards.new) end
if quickNote then bindKey(SUPER_SHIFT, "d", "Option+Shift+D", "Note in today's daily note", "Tools", quickNote.toggle) end
if pullRequests then bindKey(SUPER_SHIFT, "g", "Option+Shift+G", "PRs waiting for your review", "Tools", pullRequests.toggle) end
if hungryProcesses then bindKey(SUPER_SHIFT, "p", "Option+Shift+P", "Hungry processes and ports", "Tools", hungryProcesses.toggle) end
if diskCard then bindKey(SUPER_SHIFT, "x", "Option+Shift+X", "Disk space and cleanup", "Tools", diskCard.toggle) end
if nightLight then bindKey(SUPER_SHIFT, "z", "Option+Shift+Z", "Night light on or off", "Tools", nightLight.toggle) end
if mic then bindKey(SUPER, "m", "Option+M", "Mute or unmute the mic", "Tools", mic.toggle) end
if soundCard then bindKey(SUPER, "o", "Option+O", "Next sound output", "Tools", soundCard.nextOutput) end
if translateSelection then bindKey(SUPER, "y", "Option+Y", "Translate the selection", "Tools", translateSelection.selection) end
if airDrop then bindKey(SUPER_SHIFT, "q", "Option+Shift+Q", "Share with AirDrop", "Tools", airDrop.share) end
if waitingClaude then bindKey(SUPER_SHIFT, "a", "Option+Shift+A", "Agents waiting for you", "Tools", waitingClaude.focus) end
if sendToAgent then bindKey(SUPER, "p", "Option+P", "Send the selection or a screenshot to an agent", "Tools", sendToAgent.toggle) end
if calendarCard then bindKey(SUPER_SHIFT, "c", "Option+Shift+C", "Join the meeting starting now", "Tools", calendarCard.join) end
bindKey(SUPER_SHIFT, "space", "Option+Shift+Space", "Show or hide the bar", "Cards", run(shell.SKETCHYBAR, { "--bar", "hidden=toggle" }))
if networkCards then
  bindKey(SUPER_SHIFT, "w", "Option+Shift+W", "Wi-Fi", "Cards", networkCards.toggleWifi)
  bindKey(SUPER_SHIFT, "e", "Option+Shift+E", "Ethernet", "Cards", networkCards.toggleEthernet)
end
if bluetoothCard then bindKey(SUPER_SHIFT, "y", "Option+Shift+Y", "Bluetooth", "Cards", bluetoothCard.toggle) end
if soundCard then bindKey(SUPER_SHIFT, "v", "Option+Shift+V", "Sound", "Cards", soundCard.toggle) end
if weatherCard then bindKey(SUPER_SHIFT, "o", "Option+Shift+O", "Weather", "Cards", weatherCard.toggle) end
if batteryCard then bindKey(SUPER_SHIFT, "b", "Option+Shift+B", "Battery", "Cards", batteryCard.toggle) end
bindKey(SUPER, "escape", "Option+Escape", "System menu", "Cards", systemMenu.toggle)
bindKey(SUPER, "space", "Option+Space", "Windows, apps and commands", "Cards", windowList.toggle)
if clipboardHistory then bindKey(SUPER, "v", "Option+V", "Clipboard history", "Cards", clipboardHistory.toggle) end

-- Now playing: Music and Spotify announce every track and play-state change, so the bar
-- and the lyrics window update only then. Global, so the watchers are never garbage-collected.
-- Only while the bar's track or the lyrics window is on.
local redrawBarTrack = enabled["now-playing"] and run(shell.SKETCHYBAR, { "--trigger", "now_playing_change" }) or nil
local function playerChanged()
  if redrawBarTrack then redrawBarTrack() end
  if lyricsWindow then lyricsWindow.playerChanged() end
end
if redrawBarTrack or lyricsWindow then
  omvMediaWatchers = {
    hs.distributednotifications.new(playerChanged, "com.apple.Music.playerInfo"):start(),
    hs.distributednotifications.new(playerChanged, "com.spotify.client.PlaybackStateChanged"):start(),
  }
end

-- Ghostty owns this key, so it is listed here rather than bound.
if enabled["drop-down-terminal"] then
  keys.launchers[#keys.launchers + 1] = { label = "Option+`", description = "Drop-down terminal", group = "Apps" }
end

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
omvToggleKeyList = later(keys.toggle)
omvToggleWindows = later(windowList.toggle)
-- omv theme <name>: later() takes no arguments, so the name is carried here.
omvSetTheme = function(name) hs.timer.doAfter(0, function() themes.set(name) end) end
-- The others only while their feature is on: a script calling one that's off gets an error.
if soundCard then omvToggleSound = later(soundCard.toggle) end
if networkCards then
  omvToggleWifi = later(networkCards.toggleWifi)
  omvToggleEthernet = later(networkCards.toggleEthernet)
end
if bluetoothCard then
  omvToggleBluetooth = later(bluetoothCard.toggle)
end
if weatherCard then omvToggleWeather = later(weatherCard.toggle) end
if batteryCard then omvToggleBattery = later(batteryCard.toggle) end
if agentsCard then omvToggleAgents = later(agentsCard.toggle) end
if waitingClaude then omvFocusClaude = later(waitingClaude.focus) end
if sendToAgent then omvSendToAgent = later(sendToAgent.toggle) end
if lyricsWindow then omvToggleLyrics = later(lyricsWindow.toggle) end
if captureMenu then
  omvToggleCapture = later(captureMenu.toggle)
  omvStopRecording = later(captureMenu.stopRecording)
end
if focusMode then omvToggleFocus = later(focusMode.toggle) end
omvWorkspaces = later(workspaceCards.open)
omvWindowCard = later(workspaceCards.window)
-- AeroSpace's workspace change, while a workspace opens an app when it's empty. later() drops
-- the arguments, so the workspace is passed on here.
omvWorkspaceChanged = function(workspace)
  hs.timer.doAfter(0, function() workspaceCards.workspaceChanged(workspace) end)
end
if tailscalePanel then omvToggleTailscale = later(tailscalePanel.toggle) end
if nightLight then omvToggleNightLight = later(nightLight.toggle) end
if mic then omvToggleMic = later(mic.toggle) end
if calendarCard then
  omvToggleCalendar = later(calendarCard.toggle)
  omvJoinMeeting = later(calendarCard.join)
end
if meetingMode then omvToggleMeetingMode = later(meetingMode.toggle) end
if pullRequests then omvTogglePrs = later(pullRequests.toggle) end
if checks then
  omvToggleCi = later(checks.toggle)
  omvCiPassed = later(checks.passed)
end
if clipboardHistory then
  omvToggleClipboard = later(clipboardHistory.toggle)
  omvResumeClipboard = later(clipboardHistory.resume)
end
if hungryProcesses then omvToggleProcesses = later(hungryProcesses.toggle) end
if diskCard then omvToggleDisk = later(diskCard.toggle) end
-- The bar's outdated-packages item runs brew upgrade in a new Ghostty window on Ghostty's
-- workspace; it has no card, so it's wired here.
if enabled["brew-outdated"] then
  omvBrewUpgrade = later(function()
    run(shell.LAUNCH, { workspaceCards.homeOf("Ghostty"), shell.GHOSTTY_WINDOW, hs.configdir .. "/brew-upgrade.sh" })()
  end)
end
if reminderCards then
  omvToggleReminders = later(reminderCards.toggle)
  omvNewReminder = later(reminderCards.new)
end
if inputSource then omvNextInputSource = later(inputSource.next) end

-- SketchyBar's config calls this when it starts: a restarted bar has lost the items set
-- here, and they are only sent again when they change.
omvRedrawBar = later(function()
  if weatherCard then weatherCard.redrawBar() end
  if calendarCard then calendarCard.redrawBar() end
  if reminderCards then reminderCards.redrawBar() end
  if clipboardHistory then clipboardHistory.redrawBar() end
  if mic then mic.redrawBar() end
  if inUseDots then inUseDots.redrawBar() end
  if bluetoothCard then bluetoothCard.redrawBar() end
  if inputSource then inputSource.redrawBar() end
end)

-- Your own settings, from ~/.config/omv/hammerspoon.lua when it exists. Last, so it can
-- change anything above; an error in it is shown, and omv's keys keep working.
local personal = os.getenv("HOME") .. "/.config/omv/hammerspoon.lua"
if hs.fs.attributes(personal) then
  local ok, problem = pcall(dofile, personal)
  if not ok then
    print("omv: " .. tostring(problem))
    hs.alert.show("~/.config/omv/hammerspoon.lua: " .. tostring(problem), 6)
  end
end
