-- The permissions omv needs, as rows for the Permissions card: what each is for, whether it's
-- granted, and the Privacy pane that grants it. Has no Hammerspoon dependency, so the Lua
-- tests can run it with luajit.

local permissions = {}

local PANES = "x-apple.systempreferences:com.apple.preference.security?"

-- Order is the order on the card. Some can't be read by a script; those say to check by hand.
local LIST = {
  { key = "accessibility", label = "Accessibility · Hammerspoon", purpose = "volume and brightness pop-ups", pane = "Privacy_Accessibility" },
  { key = "aerospace", label = "Accessibility · AeroSpace", purpose = "tiling", pane = "Privacy_Accessibility" },
  { key = "swipe", label = "Accessibility · SwipeAeroSpace", purpose = "three-finger swipes", pane = "Privacy_Accessibility" },
  { key = "screen", label = "Screen Recording", purpose = "the capture menu", pane = "Privacy_ScreenCapture" },
  { key = "location", label = "Location Services", purpose = "weather and the Wi-Fi name", pane = "Privacy_LocationServices" },
  { key = "microphone", label = "Microphone", purpose = "the Sound card's level meter", pane = "Privacy_Microphone" },
  { key = "calendars", label = "Calendars", purpose = "today's events", pane = "Privacy_Calendars" },
  { key = "bluetooth", label = "Bluetooth", purpose = "the Bluetooth card", pane = "Privacy_Bluetooth" },
  { key = "disk", label = "Full Disk Access", purpose = "Do Not Disturb in the bar and the Disk card's cleanup sizes", pane = "Privacy_AllFiles" },
}

local BY_KEY = {}
for _, permission in ipairs(LIST) do BY_KEY[permission.key] = permission end

-- states: key -> true (granted), false (denied); a key left out can't be read.
function permissions.rows(states)
  local rows = {}
  for _, permission in ipairs(LIST) do
    local state = states[permission.key]
    local icon, word = "?", "check by hand"
    if state == true then icon, word = "✓", "granted" end
    if state == false then icon, word = "✗", "not granted" end
    rows[#rows + 1] = {
      id = "permission:" .. permission.key,
      icon = icon,
      label = permission.label,
      hint = permission.purpose .. " · " .. word,
    }
  end
  return rows
end

-- The System Settings pane for a row's id, or nil.
function permissions.paneUrl(id)
  local permission = BY_KEY[(id or ""):match("^permission:(.+)$") or ""]
  return permission and PANES .. permission.pane or nil
end

-- Shown once on its own, the first time omv loads; seen holds the file that records it.
function permissions.shouldOpen(seen)
  return seen == nil
end

return permissions
