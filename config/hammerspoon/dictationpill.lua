-- The dictation pill: a card-styled box at the bottom of the screen you're on, which never
-- takes focus. A header (state icon with a live dot, status and timer, a meter filling the
-- gap, and the app the words land in), then what's heard on up to four lines, and a hint; it grows
-- upwards as lines come. features/dictation.lua draws it while you talk, and docs/shoot.lua
-- draws a sample for the README.

local shell = require("shell")
local dictation = require("dictation")
local voiceagents = require("voiceagents")

local dictationPill = {}

-- A download shows in the pill only when the helper isn't ready this long after starting,
-- since it reports 0% for a language already on the Mac too.
local DOWNLOAD_SHOWN_AFTER = 1.0
local WIDTH = dictation.PILL_WIDTH
-- Characters on a line of words at the pill's width, in the bar's monospaced font.
local LINE_CHARACTERS = 60
local FONT = "JetBrainsMono Nerd Font Mono"

local function color(hex, alpha)
  return { hex = hex, alpha = alpha or 1 }
end

local pill = nil
-- The pill drawn last: its dictation.frameKey, frame and the strip the wave goes in, so a frame
-- whose text is the same isn't drawn again.
local drawn = nil
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
dictationPill.WARNING = WARNING
-- The live dot: macOS's recording red.
local LIVE = "#ff453a"
-- The header, left to right: the state icon, the status and the timer together; the meter
-- filling the gap; the app the words land in as a chip at the right edge. A hairline under it.
local ICON_X, STATUS_X, TIMER_X, CENTER_Y, RULE_Y, WORDS_Y = 18, 50, 140, 25, 44, 52
local CHIP_H, CHIP_PAD, CHIP_ICON = 26, 10, 16
local ICONS = { mic = "󰍬", lock = "󰌾", spinner = "󰑓", agent = "󰆍" }
local AGENT_HINT = "say “one …”, a name, or “reply …” · Esc cancels"

-- The sessions, numbered, one row each from y: a number badge, the folder and its state; the
-- one the words go to filled in the accent, busy ones dimmed.
local function sessionRows(elements, lines, y, tokens)
  local rowH = dictation.AGENT_ROW_HEIGHT
  for index, line in ipairs(lines) do
    local top = y + (index - 1) * rowH
    if line.chosen then
      elements[#elements + 1] = { type = "rectangle", action = "fill", fillColor = color(tokens.accent, 0.16),
        roundedRectRadii = { xRadius = 6, yRadius = 6 }, frame = { x = 12, y = top, w = WIDTH - 24, h = rowH - 2 } }
    end
    local fg = line.chosen and tokens.accent or tokens.fg
    elements[#elements + 1] = { type = "rectangle", action = "stroke", strokeColor = color(fg, line.chosen and 1 or 0.4), strokeWidth = 1,
      roundedRectRadii = { xRadius = 4, yRadius = 4 }, frame = { x = 20, y = top + 2, w = 18, h = rowH - 6 } }
    elements[#elements + 1] = text(tostring(line.number), 11, fg, { x = 20, y = top + 3, w = 18, h = 16 }, { alignment = "center" })
    local dim = line.working and not line.chosen
    elements[#elements + 1] = { type = "text", frame = { x = 48, y = top + 1, w = 260, h = 18 },
      text = hs.styledtext.new(line.label, { font = { name = FONT, size = 13 }, color = color(tokens.fg, dim and 0.45 or 1) }) }
    elements[#elements + 1] = text(line.state, 11, tokens.fg, { x = WIDTH - 230, y = top + 3, w = 210, h = 16 }, { alignment = "right" })
  end
  return #lines * rowH
end

-- What the pill says under the header, and whether a download takes the status's place.
local function body(recording)
  if not recording.ready and not recording.finishing and recording.percent
    and hs.timer.secondsSinceEpoch() - (recording.helperStarted or recording.started) >= DOWNLOAD_SHOWN_AFTER then
    return "", "once, then it stays on this Mac", "Getting " .. (recording.localeName or recording.locale) .. " for dictation… " .. recording.percent .. "%"
  end
  if recording.finishing then return recording.partial or "", "", nil end
  -- For an agent, the hint is where the words go, or what to say instead.
  if recording.agent and (recording.partial or "") == "" then return "", AGENT_HINT, nil end
  if recording.agent and recording.agentTarget then return recording.partial or "", voiceagents.resultLine(recording.agentTarget), nil end
  local hint = recording.locked and "tap Right Option to type it · Shift to copy · Esc cancels"
    or "release types it · Shift+release copies · Esc cancels"
  if recording.nextName then hint = hint .. " · Tab: " .. recording.nextName end
  if recording.secure then hint = "won't be typed here: it goes to the clipboard" end
  return recording.partial or "", hint, nil
end

local function styled(value, size, hex)
  return hs.styledtext.new(value, { font = { name = FONT, size = size }, color = color(hex) })
end

-- The app chip at the right edge; gives its width, which the meter ends 10 pt before.
local function chip(elements, header, recording, tokens)
  local warn = header.target.kind == "password"
  local fg = warn and WARNING or tokens.fg
  local name = styled(header.target.name, 13, fg)
  local textW = math.ceil(hs.drawing.getTextDrawingSize(name).w)
  local hasIcon = warn or recording.appIcon ~= nil
  local w = CHIP_PAD * 2 + textW + (hasIcon and (CHIP_ICON + 6) or 0)
  local x = WIDTH - 18 - w
  elements[#elements + 1] = { type = "rectangle", action = "strokeAndFill", fillColor = color(warn and WARNING or tokens.fg, warn and 0.12 or 0.06),
    strokeColor = color(warn and WARNING or tokens.fg, warn and 1 or 0.18), strokeWidth = 1,
    roundedRectRadii = { xRadius = CHIP_H / 2, yRadius = CHIP_H / 2 }, frame = { x = x, y = CENTER_Y - CHIP_H / 2, w = w, h = CHIP_H } }
  local textX = x + CHIP_PAD
  if warn then
    elements[#elements + 1] = text("󰌾", 13, WARNING, { x = textX, y = CENTER_Y - 9, w = CHIP_ICON, h = 18 })
    textX = textX + CHIP_ICON + 6
  elseif recording.appIcon then
    elements[#elements + 1] = { type = "image", image = recording.appIcon, frame = { x = textX, y = CENTER_Y - 8, w = CHIP_ICON, h = CHIP_ICON } }
    textX = textX + CHIP_ICON + 6
  end
  elements[#elements + 1] = { type = "text", text = name, frame = { x = textX, y = CENTER_Y - 9, w = textW + 2, h = 18 } }
  return w
end

-- The language heard now, such as EN, as a chip ending at right; gives its width.
local function languageChip(elements, code, right, tokens)
  local label = styled(code, 12, tokens.accent)
  local w = CHIP_PAD * 2 + math.ceil(hs.drawing.getTextDrawingSize(label).w)
  elements[#elements + 1] = { type = "rectangle", action = "strokeAndFill", fillColor = color(tokens.accent, 0.1),
    strokeColor = color(tokens.accent, 0.6), strokeWidth = 1, roundedRectRadii = { xRadius = CHIP_H / 2, yRadius = CHIP_H / 2 },
    frame = { x = right - w, y = CENTER_Y - CHIP_H / 2, w = w, h = CHIP_H } }
  elements[#elements + 1] = { type = "text", text = label, frame = { x = right - w + CHIP_PAD, y = CENTER_Y - 8, w = w, h = 18 } }
  return w
end

local function card(tokens, border, height)
  return { type = "rectangle", action = "strokeAndFill", fillColor = color(tokens.bg), roundedRectRadii = { xRadius = 14, yRadius = 14 },
    strokeColor = color(border), strokeWidth = 2, frame = { x = 0, y = 0, w = WIDTH, h = height } }
end

-- Draws recording, { partial, locked, finishing, stopped, left, secure, app, appIcon, problem,
-- ready, percent, started, locale, localeName }, and gives its frame and the strip, on screen,
-- where dictate.swift draws the wave, or nil when there's none.
function dictationPill.draw(recording)
  local tokens = shell.themeTokens()
  local now = hs.timer.secondsSinceEpoch()
  if recording.problem then
    return dictationPill.show({
      card(tokens, tokens.accent, 52),
      text("󰍭", 20, WARNING, { x = ICON_X, y = CENTER_Y - 13, w = 24, h = 26 }),
      text(recording.problem, 14, tokens.fg, { x = STATUS_X, y = CENTER_Y - 10, w = WIDTH - STATUS_X - 18, h = 22 }),
    }, 52)
  end
  local key = dictation.frameKey(recording, now)
  if drawn and drawn.key == key and pill and pill:isShowing() then return drawn.frame, drawn.strip end
  local header = dictation.header(recording, now)
  local words, hint, download = body(recording)
  local all = dictation.wrap(words, LINE_CHARACTERS)
  local lines = dictation.lastLines(all, dictation.MAX_LINES)
  local sessions = recording.agent and voiceagents.listLines(recording.numbered or {},
    recording.agentTarget and recording.agentTarget.row and recording.agentTarget.row.id) or {}
  local height = dictation.agentPillHeight(#lines, #sessions)
  local border = header.target.kind == "password" and WARNING or (recording.locked and tokens.fg or tokens.accent)
  local dim = recording.finishing and tokens.accent or tokens.fg
  local elements = { card(tokens, border, height), text(ICONS[header.icon], 20, dim, { x = ICON_X, y = CENTER_Y - 13, w = 24, h = 26 }) }
  -- Steady, not pulsing: a pulse would redraw the whole pill many times a second, and the wave
  -- already shows the mic is live.
  if header.live then
    elements[#elements + 1] = { type = "circle", action = "strokeAndFill", fillColor = color(LIVE), strokeColor = color(tokens.bg),
      strokeWidth = 2, center = { x = ICON_X + 19, y = CENTER_Y - 10 }, radius = 4.5 }
  end
  local chipWidth = chip(elements, header, recording, tokens)
  if header.language then chipWidth = chipWidth + 6 + languageChip(elements, header.language, WIDTH - 18 - chipWidth - 6, tokens) end
  local strip = nil
  if download then
    elements[#elements + 1] = text(download, 13, tokens.fg, { x = STATUS_X, y = CENTER_Y - 9, w = WIDTH - 18 - chipWidth - 10 - STATUS_X, h = 18 })
  else
    elements[#elements + 1] = text(header.status, 14, dim, { x = STATUS_X, y = CENTER_Y - 10, w = TIMER_X - STATUS_X - 6, h = 22 })
    elements[#elements + 1] = text(header.timer, 13, header.warning and WARNING or tokens.accent, { x = TIMER_X, y = CENTER_Y - 9, w = 44, h = 18 })
    strip = dictation.meterLayout(chipWidth)
  end
  elements[#elements + 1] = { type = "rectangle", action = "fill", fillColor = color(tokens.fg, 0.12), frame = { x = 16, y = RULE_Y, w = WIDTH - 32, h = 1 } }
  local wordsY = WORDS_Y + sessionRows(elements, sessions, WORDS_Y, tokens)
  -- Past four lines, the oldest shown fades, as the newest words push it up.
  for index, line in ipairs(lines) do
    local faded = index == 1 and #all > dictation.MAX_LINES
    elements[#elements + 1] = { type = "text", frame = { x = 16, y = wordsY + (index - 1) * dictation.LINE_HEIGHT, w = WIDTH - 32, h = dictation.LINE_HEIGHT },
      text = hs.styledtext.new(line, { font = { name = FONT, size = 14 }, color = color(tokens.fg, faded and 0.45 or 1) }) }
  end
  local hintColor = recording.secure and WARNING or tokens.fg
  local kind = recording.agent and recording.agentTarget and recording.agentTarget.kind
  if kind == "paste" then hintColor = tokens.accent elseif kind == "copy" then hintColor = WARNING end
  elements[#elements + 1] = text(hint, 11, hintColor, { x = 16, y = height - 26, w = WIDTH - 32, h = 18 })
  local frame = dictationPill.show(elements, height)
  local onScreen = strip and { x = frame.x + strip.x, y = frame.y, w = strip.w } or nil
  drawn = { key = key, frame = frame, strip = onScreen }
  return frame, onScreen
end

-- After the words went somewhere: delivery { kind, message, hint } from dictation.delivery,
-- with a check when typed and the clipboard when copied, for a moment.
function dictationPill.confirm(delivery)
  local tokens = shell.themeTokens()
  local elements = {
    card(tokens, tokens.accent, 52),
    text(delivery.kind == "type" and "󰄬" or "󰅍", 20, tokens.fg, { x = ICON_X, y = CENTER_Y - 13, w = 24, h = 26 }),
    text(delivery.message, 14, tokens.fg, { x = STATUS_X, y = CENTER_Y - 10, w = 380, h = 22 }),
  }
  if delivery.hint then
    elements[#elements + 1] = text(delivery.hint, 12, tokens.accent, { x = WIDTH - 118, y = CENTER_Y - 8, w = 100, h = 18 }, { alignment = "right" })
  end
  local frame = dictationPill.show(elements, 52)
  hideLater = hs.timer.doAfter(delivery.kind == "type" and 1.2 or 2, dictationPill.hide)
  return frame
end

-- After a release that named no session: c { heard, prompt, rows }. What was heard, the
-- sessions numbered, and the words a digit sends; orange, as nothing has gone anywhere yet.
function dictationPill.choosing(c)
  local tokens = shell.themeTokens()
  local sessions = voiceagents.listLines(c.rows)
  local heard = dictation.lastLines(dictation.wrap("heard: “" .. c.heard .. "”", LINE_CHARACTERS), 2)
  local height = dictation.agentPillHeight(#heard, #sessions)
  local elements = {
    card(tokens, WARNING, height),
    text(ICONS.agent, 20, WARNING, { x = ICON_X, y = CENTER_Y - 13, w = 24, h = 26 }),
    text(c.note or "Which one?", 14, tokens.fg, { x = STATUS_X, y = CENTER_Y - 10, w = WIDTH - STATUS_X - 18, h = 22 }),
    { type = "rectangle", action = "fill", fillColor = color(tokens.fg, 0.12), frame = { x = 16, y = RULE_Y, w = WIDTH - 32, h = 1 } },
  }
  local wordsY = WORDS_Y + sessionRows(elements, sessions, WORDS_Y, tokens)
  for index, line in ipairs(heard) do
    elements[#elements + 1] = { type = "text", frame = { x = 16, y = wordsY + (index - 1) * dictation.LINE_HEIGHT, w = WIDTH - 32, h = dictation.LINE_HEIGHT },
      text = hs.styledtext.new(line, { font = { name = FONT, size = 13 }, color = color(tokens.fg, 0.55) }) }
  end
  elements[#elements + 1] = text("press 1–" .. #c.rows .. " to send “" .. c.prompt .. "” · Esc copies it", 11, tokens.fg,
    { x = 16, y = height - 26, w = WIDTH - 32, h = 18 })
  return dictationPill.show(elements, height)
end

-- While talk-back speaks: { project, line }, with a speaker, "<project> finished", the line
-- as it's spoken, and how to answer.
function dictationPill.speaking(item)
  local tokens = shell.themeTokens()
  local lines = dictation.lastLines(dictation.wrap(item.line, LINE_CHARACTERS), dictation.MAX_LINES)
  local height = dictation.pillHeight(#lines)
  local elements = {
    card(tokens, tokens.accent, height),
    text("󰕾", 20, tokens.accent, { x = ICON_X, y = CENTER_Y - 13, w = 24, h = 26 }),
    text(item.project .. " finished", 14, tokens.fg, { x = STATUS_X, y = CENTER_Y - 10, w = WIDTH - STATUS_X - 18, h = 22 }),
    { type = "rectangle", action = "fill", fillColor = color(tokens.fg, 0.12), frame = { x = 16, y = RULE_Y, w = WIDTH - 32, h = 1 } },
  }
  for index, line in ipairs(lines) do
    elements[#elements + 1] = text(line, 14, tokens.fg, { x = 16, y = WORDS_Y + (index - 1) * dictation.LINE_HEIGHT, w = WIDTH - 32, h = dictation.LINE_HEIGHT })
  end
  elements[#elements + 1] = text(item.hint or "hold Right Command to reply", 11, tokens.fg, { x = 16, y = height - 26, w = WIDTH - 32, h = 18 })
  return dictationPill.show(elements, height)
end

function dictationPill.show(elements, height)
  drawn = nil
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
  drawn = nil
  if pill then pill:hide() end
end

return dictationPill
