-- The dictation pill: a card-styled box at the bottom of the screen you're on, which never
-- takes focus. It shows the waveform, what's heard on up to four lines, and a hint; it grows
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

local function elapsed(started)
  local seconds = math.floor(hs.timer.secondsSinceEpoch() - started)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- What the pill says for the recording now: its status, the words, and the hint under them.
local function pillLines(recording)
  if recording.problem then return "", recording.problem, "" end
  if recording.finishing then return "Finishing…", recording.partial or "", "" end
  if not recording.ready and recording.percent and hs.timer.secondsSinceEpoch() - recording.started >= DOWNLOAD_SHOWN_AFTER then
    return "Getting " .. recording.locale .. " for dictation… " .. recording.percent .. "%", "", "once, then it stays on this Mac"
  end
  local status = recording.locked and "Locked" or "Listening…"
  local hint = recording.locked and "tap Right Option to type it · Esc cancels" or "release types it · Esc cancels"
  return status, recording.partial or "", hint
end

-- Draws recording, { partial, history, locked, finishing, problem, ready, percent, started,
-- locale }, and gives the frame it's drawn in.
function dictationPill.draw(recording)
  local tokens = shell.themeTokens()
  local status, words, hint = pillLines(recording)
  local all = dictation.wrap(words, LINE_CHARACTERS)
  local lines = dictation.lastLines(all, dictation.MAX_LINES)
  local height = dictation.pillHeight(#lines)
  local elements = {
    { type = "rectangle", action = "strokeAndFill", fillColor = color(tokens.bg), roundedRectRadii = { xRadius = 14, yRadius = 14 },
      strokeColor = color(recording.locked and tokens.fg or tokens.accent), strokeWidth = 2, frame = { x = 0, y = 0, w = WIDTH, h = height } },
    text(recording.problem and "󰍭" or "󰍬", 20, tokens.fg, { x = 16, y = 12, w = 24, h = 26 }),
  }
  -- The waveform: one bar per moment, newest at the right; silence is a dotted line.
  local history = recording.history or {}
  for index = 1, 24 do
    local level = recording.finishing and 0 or (history[#history - 24 + index] or 0)
    local barHeight = 3 + math.floor(19 * level)
    elements[#elements + 1] = { type = "rectangle", action = "fill", fillColor = color(tokens.fg, level > 0.04 and 1 or 0.35),
      roundedRectRadii = { xRadius = 1.5, yRadius = 1.5 }, frame = { x = 46 + (index - 1) * 5, y = 25 - barHeight / 2, w = 3, h = barHeight } }
  end
  elements[#elements + 1] = text(status, 14, tokens.fg, { x = 176, y = 14, w = 300, h = 22 })
  if recording.locked and not recording.finishing then
    elements[#elements + 1] = text(elapsed(recording.started), 13, tokens.fg, { x = WIDTH - 80, y = 15, w = 64, h = 20 }, { alignment = "right" })
  end
  -- Past four lines, the oldest shown fades, as the newest words push it up.
  for index, line in ipairs(lines) do
    local faded = index == 1 and #all > dictation.MAX_LINES
    elements[#elements + 1] = { type = "text", frame = { x = 16, y = 44 + (index - 1) * dictation.LINE_HEIGHT, w = WIDTH - 32, h = dictation.LINE_HEIGHT },
      text = hs.styledtext.new(line, { font = { name = FONT, size = 14 }, color = color(tokens.fg, faded and 0.45 or 1) }) }
  end
  elements[#elements + 1] = text(hint, 11, tokens.fg, { x = 16, y = height - 26, w = WIDTH - 32, h = 18 })
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
