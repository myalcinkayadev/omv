-- Behavior of docs/shots.lua, the list of README screenshots and the sample data they're
-- drawn from. Run through shots_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local shots = dofile(arg[1] .. "/docs/shots.lua")

-- The desktop shots need real windows, so they're taken by hand.
local BY_HAND = { ["workspace-1.png"] = true, ["tabbed.png"] = true, ["bar.png"] = true }
local NOW = os.time({ year = 2026, month = 11, day = 13, hour = 10, min = 20 })

local ok, list = pcall(shots.build, NOW)
check.that("should build every card shot without Hammerspoon", ok and type(list) == "table" and #list > 0)
if not ok then print("    " .. tostring(list)); check.finish() end

local readme = io.open(arg[1] .. "/README.md"):read("*a")
local shown = {}
for file in readme:gmatch("docs/([%w%-]+%.png)") do shown[file] = true end

local names, unique, sized, pages, inReadme = {}, true, true, true, true
for _, shot in ipairs(list) do
  if names[shot.file] then unique = false end
  names[shot.file] = true
  if shot.kind == "card" then
    if type(shot.html) ~= "string" or shot.html == "" then pages = false end
    if not (shot.crop or (shot.width and shot.height)) then sized = false end
  end
  if not shown[shot.file] then inReadme = false; print("    not in the README: " .. shot.file) end
end
check.that("should give every shot a unique file name", unique)
check.that("should give every card shot a page", pages)
check.that("should give every card shot a size, or a part of the page to crop to", sized)
check.that("should only make images the README shows", inReadme)

local covered = true
for file in pairs(shown) do
  if not BY_HAND[file] and not names[file] then covered = false; print("    no shot for: " .. file) end
end
check.that("should cover every image in the README except the desktop shots", covered)

local home, user = os.getenv("HOME"), os.getenv("USER")
local private = false
for _, shot in ipairs(list) do
  if shot.html and ((home and check.contains(shot.html, home)) or (user and #user > 2 and check.contains(shot.html, user))) then
    private = true; print("    real data in: " .. shot.file)
  end
end
check.that("should keep your home folder and user name out of every shot's page", not private)

local again = shots.build(NOW)
local same = #again == #list
for index, shot in ipairs(list) do same = same and again[index].html == shot.html end
check.that("should build the same pages for the same clock", same)

check.finish()
