-- Takes the README's card screenshots, run inside Hammerspoon by docs/shoot.sh. Each card
-- opens on the built-in Retina screen, so images come out at 2x, and is saved to docs/.
-- Loaded with dofile, it returns a function: shoot(docsDir, only, doneFile), where only is
-- a set of file names to take, or nil for all, and doneFile is written when it finishes.

local shell = require("shell")
local osdFeature = require("features.osd")

local SCREENCAPTURE = "/usr/sbin/screencapture"
-- How long a card gets to draw before it's captured, and the gap before the next one.
local SETTLE_SECONDS, NEXT_SECONDS = 1.0, 0.3
-- The note editor sizes itself, so it opens in a frame this tall and is cut to its page.
local SELF_SIZED_HEIGHT = 600

local function builtinScreen()
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:name():find("Built%-in") then return screen end
  end
  return hs.screen.mainScreen()
end

-- The pointer goes to a corner of the built-in screen: cards open on the pointer's screen,
-- and a pointer over a row would select it.
local function parkPointer(screen)
  local frame = screen:frame()
  hs.mouse.absolutePosition({ x = frame.x + 4, y = frame.y + frame.h - 4 })
end

local function centered(screen, width, height)
  local frame = screen:fullFrame()
  return hs.geometry.rect(math.floor(frame.x + (frame.w - width) / 2), math.floor(frame.y + (frame.h - height) / 2), width, height)
end

-- Calls back with nil when saved, or screencapture's complaint, as when the screen is locked.
local function capture(rect, file, onDone)
  hs.task.new(SCREENCAPTURE, function(code, _, errors)
    onDone(code ~= 0 and ((errors or ""):gsub("%s+$", "")) or nil)
  end, { "-x", string.format("-R%d,%d,%d,%d", rect.x, rect.y, rect.w, rect.h), file }):start()
end

-- The rect of the page's element selector, in screen points.
local function elementRect(frame, selector, onRect)
  local script = "(function(){var b=document.querySelector('" .. selector .. "').getBoundingClientRect();"
    .. "return [b.left,b.top,b.width,b.height].join(',')})()"
  shell.view():evaluateJavaScript(script, function(result)
    local x, y, w, h = tostring(result):match("([%d.]+),([%d.]+),([%d.]+),([%d.]+)")
    if not x then return onRect(frame) end
    onRect(hs.geometry.rect(frame.x + math.floor(x), frame.y + math.floor(y), math.ceil(w), math.ceil(h)))
  end)
end

-- Shows a shot and calls back with the rect to capture once it has drawn.
local function show(shot, screen, onReady)
  if shot.kind == "osd" then
    local frame = osdFeature.show(shot.icon, shot.level)
    return hs.timer.doAfter(0.4, function() onReady(hs.geometry.rect(frame.x, frame.y, frame.w, frame.h)) end)
  end
  if shot.kind == "live" then
    require(shot.feature)[shot.call]()
    return hs.timer.doAfter(SETTLE_SECONDS, function() onReady(shell.view():frame()) end)
  end
  local frame
  if shot.big then frame = screen:fullFrame()
  else frame = centered(screen, shot.width, shot.height or SELF_SIZED_HEIGHT) end
  shell.show("shot", frame, shot.html, function() end, { keepOnBlur = true })
  hs.timer.doAfter(SETTLE_SECONDS, function()
    if shot.script then shell.view():evaluateJavaScript(shot.script) end
    hs.timer.doAfter(shot.script and 0.3 or 0, function()
      if shot.crop then return elementRect(frame, shot.crop, onReady) end
      onReady(frame)
    end)
  end)
end

local function claudeLogo()
  local image = hs.image.imageFromPath(shell.HOME .. "/.config/sketchybar/icons/claude.png")
  return image and image:encodeAsURLString() or nil
end

return function(docs, only, doneFile)
  local list = dofile(docs .. "/shots.lua").build(os.time(), claudeLogo())
  local queue = {}
  for _, shot in ipairs(list) do
    if not only or only[shot.file] then queue[#queue + 1] = shot end
  end
  local screen = builtinScreen()
  local taken = {}

  local function finish()
    shell.close()
    local file = io.open(doneFile, "w")
    file:write(table.concat(taken, "\n") .. "\n")
    file:close()
  end

  local function nextShot(index)
    local shot = queue[index]
    if not shot then return finish() end
    shell.close()
    parkPointer(screen)
    local ok, problem = pcall(show, shot, screen, function(rect)
      capture(rect, docs .. "/" .. shot.file, function(problem)
        taken[#taken + 1] = problem and ("FAILED " .. shot.file .. ": " .. problem) or shot.file
        hs.timer.doAfter(NEXT_SECONDS, function() nextShot(index + 1) end)
      end)
    end)
    if not ok then
      taken[#taken + 1] = "FAILED " .. shot.file .. ": " .. tostring(problem)
      nextShot(index + 1)
    end
  end

  nextShot(1)
end
