-- The dictation pill: a card-styled box at the bottom of the screen you're on, which never
-- takes focus. A header of fixed slots (state icon with a live dot, waveform, status, timer,
-- and the app the words land in), then what's heard on up to four lines, and a hint; it grows
-- upwards as lines come. features/dictation.lua draws it while you talk, and docs/shoot.lua
-- draws a sample for the README.

local shell = require("shell")
local dictation = require("dictation")

local dictationPill = {}

-- A download shows in the pill only when the helper isn't ready this long after starting,
-- since it reports 0% for a language already on the Mac too.
local DOWNLOAD_SHOWN_AFTER = 1.0
local WIDTH = 560
-- Characters on a line of words at the pill's width, in the bar's monospaced font.
local LINE_CHARACTERS = 60
local FONT = "JetBrainsMono Nerd Font Mono"

local function color(hex, alpha)
  return { hex = hex, alpha = alpha or 1 }
end

local pill = nil
-- Hides the confirmation; stopped when the pill is drawn again before it fires.
local hideLater = nil

-- The pill grows upwards from a fixed bottom edge as lines of words come.
local function placed(height)
  local frame = shell.screen():frame()
  return { x = frame.x + (frame.w - WIDTH) / 2, y = frame.y + frame.h - height - 120, w = WIDTH, h = height }
end

local function text(value, size, hex, frame, options)
  options = options or {}
  return { type = "text", frame = frame, text = hs.styledtext.new(value, {
    font = { name = FONT, size = size }, color = color(hex),
    paragraphStyle = { lineBreak = options.lineBreak or "truncateTail", alignment = options.alignment or "left" },
  }) }
end

-- Orange, for a countdown and a password field.
local WARNING = "#f0a35e"
-- The live dot: macOS's recording red.
local LIVE = "#ff453a"
-- The header's slots, left to right: the state icon, the waveform, the status, the timer and
-- the app the words land in. They keep their places in every state, so nothing jumps.
local ICON_X, WAVE_X, STATUS_X, TIMER_X, TARGET_X = 18, 50, 180, 306, 402
local TIMER_W, TARGET_W, CENTER_Y = 84, 140, 25
local ICONS = { mic = "󰍬", lock = "󰌾", spinner = "󰑓" }

-- What the pill says under the header, and whether a download takes the status's place.
local function body(recording)
  if not recording.ready and not recording.finishing and recording.percent
    and hs.timer.secondsSinceEpoch() - recording.started >= DOWNLOAD_SHOWN_AFTER then
    return "", "once, then it stays on this Mac", "Getting " .. (recording.localeName or recording.locale) .. " for dictation… " .. recording.percent .. "%"
  end
  if recording.finishing then return recording.partial or "", "", nil end
  local hint = recording.locked and "tap Right Option to type it · Shift to review · Esc cancels"
    or "release types it · Shift+release to review · Esc cancels"
  if recording.secure then hint = "won't be typed here: it goes to the clipboard" end
  return recording.partial or "", hint, nil
end

local function waveform(elements, recording, fg)
  if recording.reduceMotion then
    local level = recording.finishing and 0 or ((recording.history or {})[#(recording.history or {})] or 0)
    elements[#elements + 1] = { type = "rectangle", action = "fill", fillColor = color(fg, 0.25), roundedRectRadii = { xRadius = 3, yRadius = 3 },
      frame = { x = WAVE_X, y = CENTER_Y - 3, w = 118, h = 6 } }
    elements[#elements + 1] = { type = "rectangle", action = "fill", fillColor = color(fg), roundedRectRadii = { xRadius = 3, yRadius = 3 },
      frame = { x = WAVE_X, y = CENTER_Y - 3, w = math.max(6, 118 * level), h = 6 } }
    return
  end
  -- Silence is a flat line; speech rises out of it in bars, newest at the right.
  elements[#elements + 1] = { type = "rectangle", action = "fill", fillColor = color(fg, 0.3), frame = { x = WAVE_X, y = CENTER_Y - 1, w = 118, h = 2 } }
  if recording.finishing then return end
  local history = recording.history or {}
  for index = 1, 24 do
    local level = history[#history - 24 + index] or 0
    if level > 0.04 then
      local barHeight = 3 + math.floor(19 * level)
      elements[#elements + 1] = { type = "rectangle", action = "fill", fillColor = color(fg), roundedRectRadii = { xRadius = 1.5, yRadius = 1.5 },
        frame = { x = WAVE_X + (index - 1) * 5, y = CENTER_Y - barHeight / 2, w = 3, h = barHeight } }
    end
  end
end

local function target(elements, header, recording, fg)
  local warn = header.target.kind == "password"
  local x = TARGET_X
  if warn then
    elements[#elements + 1] = text("󰌾", 13, WARNING, { x = x, y = CENTER_Y - 9, w = 16, h = 18 })
  elseif recording.appIcon then
    elements[#elements + 1] = { type = "image", image = recording.appIcon, frame = { x = x, y = CENTER_Y - 8, w = 16, h = 16 } }
  end
  elements[#elements + 1] = text(header.target.name, 13, warn and WARNING or fg, { x = x + 22, y = CENTER_Y - 9, w = TARGET_W - 22, h = 18 })
end

-- Draws recording, { partial, history, locked, finishing, stopped, left, secure, app, appIcon,
-- problem, ready, percent, started, locale, localeName, reduceMotion }, and gives its frame.
function dictationPill.draw(recording)
  local tokens = shell.themeTokens()
  local now = hs.timer.secondsSinceEpoch()
  if recording.problem then
    local elements = {
      { type = "rectangle", action = "strokeAndFill", fillColor = color(tokens.bg), roundedRectRadii = { xRadius = 14, yRadius = 14 },
        strokeColor = color(tokens.accent), strokeWidth = 2, frame = { x = 0, y = 0, w = WIDTH, h = 52 } },
      text("󰍭", 20, WARNING, { x = ICON_X, y = CENTER_Y - 13, w = 24, h = 26 }),
      text(recording.problem, 14, tokens.fg, { x = WAVE_X, y = CENTER_Y - 10, w = WIDTH - WAVE_X - 18, h = 22 }),
    }
    return dictationPill.show(elements, 52)
  end
  local header = dictation.header(recording, now)
  local words, hint, download = body(recording)
  local all = dictation.wrap(words, LINE_CHARACTERS)
  local lines = dictation.lastLines(all, dictation.MAX_LINES)
  local height = dictation.pillHeight(#lines)
  local border = header.target.kind == "password" and WARNING or (recording.locked and tokens.fg or tokens.accent)
  local elements = {
    { type = "rectangle", action = "strokeAndFill", fillColor = color(tokens.bg), roundedRectRadii = { xRadius = 14, yRadius = 14 },
      strokeColor = color(border), strokeWidth = 2, frame = { x = 0, y = 0, w = WIDTH, h = height } },
    text(ICONS[header.icon], 20, tokens.fg, { x = ICON_X, y = CENTER_Y - 13, w = 24, h = 26 }),
  }
  if header.live then
    local pulse = recording.reduceMotion and 1 or (0.55 + 0.45 * math.abs(math.sin(now * 3)))
    elements[#elements + 1] = { type = "circle", action = "strokeAndFill", fillColor = color(LIVE, pulse), strokeColor = color(tokens.bg),
      strokeWidth = 2, center = { x = ICON_X + 19, y = CENTER_Y - 10 }, radius = 4.5 }
  end
  waveform(elements, recording, tokens.fg)
  if download then
    elements[#elements + 1] = text(download, 13, tokens.fg, { x = STATUS_X, y = CENTER_Y - 9, w = TARGET_X - STATUS_X - 12, h = 18 })
  else
    elements[#elements + 1] = text(header.status, 14, tokens.fg, { x = STATUS_X, y = CENTER_Y - 10, w = TIMER_X - STATUS_X - 12, h = 22 })
    elements[#elements + 1] = text(header.timer, 13, header.warning and WARNING or tokens.fg, { x = TIMER_X, y = CENTER_Y - 9, w = TIMER_W, h = 18 },
      { alignment = "right" })
  end
  target(elements, header, recording, tokens.fg)
  -- Past four lines, the oldest shown fades, as the newest words push it up.
  for index, line in ipairs(lines) do
    local faded = index == 1 and #all > dictation.MAX_LINES
    elements[#elements + 1] = { type = "text", frame = { x = 16, y = 44 + (index - 1) * dictation.LINE_HEIGHT, w = WIDTH - 32, h = dictation.LINE_HEIGHT },
      text = hs.styledtext.new(line, { font = { name = FONT, size = 14 }, color = color(tokens.fg, faded and 0.45 or 1) }) }
  end
  elements[#elements + 1] = text(hint, 11, recording.secure and WARNING or tokens.fg, { x = 16, y = height - 26, w = WIDTH - 32, h = 18 })
  return dictationPill.show(elements, height)
end

-- After typing: how many words, how many ums were dropped, and that ⌘Z undoes it, for a moment.
function dictationPill.confirm(words, dropped)
  local tokens = shell.themeTokens()
  local said = "Typed " .. words .. (words == 1 and " word" or " words") .. (dropped > 0 and (" · " .. dropped .. " ums dropped") or "")
  local elements = {
    { type = "rectangle", action = "strokeAndFill", fillColor = color(tokens.bg), roundedRectRadii = { xRadius = 14, yRadius = 14 },
      strokeColor = color(tokens.accent), strokeWidth = 2, frame = { x = 0, y = 0, w = WIDTH, h = 52 } },
    text("󰄬", 20, tokens.fg, { x = ICON_X, y = CENTER_Y - 13, w = 24, h = 26 }),
    text(said, 14, tokens.fg, { x = WAVE_X, y = CENTER_Y - 10, w = 380, h = 22 }),
    text("⌘Z undoes", 12, tokens.fg, { x = WIDTH - 118, y = CENTER_Y - 8, w = 100, h = 18 }, { alignment = "right" }),
  }
  local frame = dictationPill.show(elements, 52)
  hideLater = hs.timer.doAfter(1.2, dictationPill.hide)
  return frame
end

function dictationPill.show(elements, height)
  if hideLater then hideLater:stop() end
  hideLater = nil
  if not pill then
    pill = hs.canvas.new(placed(height)):level(hs.canvas.windowLevels.overlay):behavior({ "canJoinAllSpaces", "transient" })
  end
  local frame = placed(height)
  pill:frame(frame):replaceElements(elements):show()
  return frame
end

function dictationPill.hide()
  if pill then pill:hide() end
end

return dictationPill
