-- The browser's open tabs, for the palette: the AppleScript that reads them all, their rows,
-- and the AppleScript that brings one to the front. The browser is the one named in
-- ~/.config/omv/apps. Safari calls the shown tab "current tab" and its title "name"; Helium,
-- Chrome and the other Chromium browsers say "active tab index" and "title".
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local tabs = {}

-- A tab's fields end with the unit separator and each tab with the record separator: control
-- characters a URL can't hold and a page title next to never does, unlike a tab, a newline
-- or a "|".
tabs.FIELD_END = "\31"
tabs.RECORD_END = "\30"

-- The name goes into AppleScript, so a quote or backslash could change what it runs.
local function usable(browser)
  return type(browser) == "string" and browser ~= "" and not browser:find('["\\]')
end

local function isSafari(browser)
  return browser == "Safari"
end

-- Windows are named by id, not index: their index is their order on screen, which changes
-- whenever another of them comes to the front. Tabs are read a property at a time, so the
-- browser answers three questions however many tabs are open. The check that the browser
-- runs keeps the script from launching it.
function tabs.readScript(browser)
  if not usable(browser) then return nil end
  local title = isSafari(browser) and "name" or "title"
  return table.concat({
    'if application "' .. browser .. '" is not running then return ""',
    "set fieldEnd to character id 31",
    "set recordEnd to character id 30",
    'tell application "' .. browser .. '"',
    "  set windowIds to id of every window",
    "  set titles to " .. title .. " of every tab of every window",
    "  set links to URL of every tab of every window",
    "end tell",
    "set found to {}",
    "repeat with w from 1 to count of windowIds",
    "  set windowTitles to item w of titles",
    "  set windowLinks to item w of links",
    "  repeat with t from 1 to count of windowTitles",
    "    set end of found to ((item w of windowIds) as text) & fieldEnd & t & fieldEnd & my textOf(item t of windowTitles) & fieldEnd & my textOf(item t of windowLinks) & recordEnd",
    "  end repeat",
    "end repeat",
    "set AppleScript's text item delimiters to \"\"",
    "return found as text",
    "on textOf(value)",
    '  if value is missing value then return ""',
    "  return value as text",
    "end textOf",
  }, "\n")
end

-- Shows tab index of the window with windowId, brings that window to the front and the
-- browser with it. nil for a name that can't go into AppleScript or an id that isn't a number.
function tabs.focusScript(browser, windowId, index)
  if not usable(browser) or type(windowId) ~= "number" or type(index) ~= "number" then return nil end
  local show = isSafari(browser) and ("  set current tab of shown to tab " .. index .. " of shown")
    or ("  set active tab index of shown to " .. index)
  return table.concat({
    'if application "' .. browser .. '" is not running then return',
    'tell application "' .. browser .. '"',
    "  set shown to window id " .. windowId,
    show,
    "  set index of shown to 1",
    "  activate",
    "end tell",
  }, "\n")
end

-- The read script's answer as { window, index, title, url }, in the browser's order. A title
-- holding the field separator keeps it; one holding the record separator loses its tab,
-- which no longer starts with two numbers.
function tabs.parse(output)
  local found = {}
  for record in tostring(output or ""):gmatch("[^\30]+") do
    local window, index, rest = record:match("^(%d+)\31(%d+)\31(.*)$")
    local url = rest and rest:match("\31([^\31]*)$")
    if url then
      found[#found + 1] = { window = tonumber(window), index = tonumber(index),
        title = rest:sub(1, #rest - #url - 1), url = url }
    end
  end
  return found
end

-- "https://user@docs.example.com:8080/a" is docs.example.com; a URL without one, such as
-- about:blank, shows whole.
function tabs.host(url)
  return url:match("^%a[%w+.-]*://[^/@]*@([^/:?#]+)") or url:match("^%a[%w+.-]*://([^/:?#]+)") or url
end

-- A title on one line; a tab without one shows its URL.
local function label(tab)
  local title = tab.title:gsub("%s+", " "):match("^ ?(.-) ?$")
  return title ~= "" and title or tab.url
end

-- One palette row per tab, its id tab:<window id>:<tab index>.
function tabs.rows(output)
  local rows = {}
  for _, tab in ipairs(tabs.parse(output)) do
    rows[#rows + 1] = { id = "tab:" .. tab.window .. ":" .. tab.index, icon = "󰖟", label = label(tab),
      hint = tabs.host(tab.url), group = "Tabs" }
  end
  return rows
end

return tabs
