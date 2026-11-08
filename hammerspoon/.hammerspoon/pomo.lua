-- The Pomodoro break cards: what each of the three cards says, the tips, and today's count.
-- init.lua decides when each card shows. Nothing starts on its own: each step waits for a pick.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local pomo = {}

pomo.POMO_SECONDS = 25 * 60
pomo.BREAK_SECONDS = 5 * 60
pomo.POSTPONE_SECONDS = 5 * 60
pomo.LONG_BREAK_SECONDS = 15 * 60
pomo.WARNING_SECONDS = 30
local GOAL = 4

-- Every 4th pomo of the day earns a 15-minute break; the others get 5.
function pomo.breakSeconds(count)
  return (count > 0 and count % GOAL == 0) and pomo.LONG_BREAK_SECONDS or pomo.BREAK_SECONDS
end

-- True in a pomo's last 30 seconds, when the bar gives a quiet heads-up.
function pomo.warning(reminder, now)
  if reminder.kind ~= "pomo" and reminder.kind ~= "postponed" then return false end
  local left = reminder.due - now
  return left > 0 and left <= pomo.WARNING_SECONDS
end

pomo.TIPS = {
  "Stand up and stretch your shoulders.",
  "Look at something far away for a minute.",
  "Get a glass of water.",
  "Walk around the room.",
  "Close your eyes and take a few slow breaths.",
  "Roll your neck and wrists.",
}

function pomo.tip(number)
  return pomo.TIPS[(number - 1) % #pomo.TIPS + 1]
end

-- Dots for today's count, in rows of 4: 2 shows 2 of 4, 5 shows 5 of 8.
function pomo.dots(count)
  return { filled = count, total = math.max(GOAL, math.ceil(count / GOAL) * GOAL) }
end

local function kicker(prefix, count)
  return prefix .. " · " .. count .. " OF " .. pomo.dots(count).total .. " TODAY"
end

function pomo.task(task)
  return (task and task ~= "") and task or "Pomodoro"
end

-- Each row has a letter key: b for break, r to be reminded again, c to cancel.

-- Card 1, when a pomo is due. "5 more minutes" is offered once per pomo.
function pomo.doneScreen(context)
  local minutes = math.floor(pomo.breakSeconds(context.count) / 60)
  local rows = { { id = "break.start", icon = "󰅶", label = "Start " .. minutes .. "-minute break", key = "b", hint = "b" } }
  if not context.postponed then
    rows[#rows + 1] = { id = "pomo.postpone", icon = "󰔛", label = "5 more minutes", key = "r", hint = "r" }
  end
  rows[#rows + 1] = { id = "break.skip", icon = "󰒭", label = "Skip break", key = "c", hint = "c" }
  return {
    kicker = kicker("POMODORO DONE", context.count),
    dots = pomo.dots(context.count),
    title = "Time for a break.",
    sub = pomo.task(context.task) .. " · " .. math.floor(pomo.POMO_SECONDS / 60) .. " minutes",
    rows = rows,
    selected = 1,
  }
end

-- Card 2, during the break. The page ticks the countdown down to ends itself.
function pomo.breakScreen(context)
  return {
    kicker = kicker("BREAK", context.count),
    countdown = { ends = context.ends, seconds = context.seconds },
    tip = pomo.tip(context.tip),
    rows = { { id = "break.end", icon = "󰓛", label = "End break early", key = "c", hint = "c" } },
    selected = 1,
  }
end

-- Card 3, when the break is over or skipped.
function pomo.overScreen(context)
  return {
    kicker = "BREAK OVER",
    dots = pomo.dots(context.count),
    title = "Back to work?",
    sub = "Next: " .. pomo.task(context.task),
    rows = {
      { id = "pomo.next", icon = "󰐊", label = "Start next pomo", hint = math.floor(pomo.POMO_SECONDS / 60) .. " min" },
      { id = "pomo.stop", icon = "󰐥", label = "Done for now", key = "c", hint = "c" },
    },
    selected = 1,
  }
end

-- Today's count is saved as "2026-11-08<tab>2". A new day starts the count over.
function pomo.decode(text)
  local day, count = text:match("^(%d+%-%d+%-%d+)\t(%d+)")
  return { day = day, count = tonumber(count) or 0 }
end

function pomo.encode(record)
  return (record.day or "") .. "\t" .. record.count
end

function pomo.countFor(record, today)
  return record.day == today and record.count or 0
end

function pomo.finished(record, today)
  return { day = today, count = pomo.countFor(record, today) + 1 }
end

return pomo
