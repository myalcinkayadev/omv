-- The calendar card opened by clicking the clock. Weeks start on Monday and carry their
-- ISO week number, and every month shows six of them. Left and Right change month, T returns to today, Escape closes.
-- Keys reach init.lua through the "omv" message handler as { type, id }.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = require("card")

local calendar = {}

local DAY_SECONDS = 24 * 60 * 60

-- Noon keeps daylight-saving changes from moving a date to the day before.
local function timeOf(year, month, day)
  return os.time({ year = year, month = month, day = day, hour = 12 })
end

-- os.date's wday counts from Sunday = 1. This returns Monday = 1 through Sunday = 7.
local function weekdayOf(time)
  return (os.date("*t", time).wday + 5) % 7 + 1
end

function calendar.shift(year, month, delta)
  local index = year * 12 + (month - 1) + delta
  return math.floor(index / 12), index % 12 + 1
end

function calendar.month(year, month, today)
  local first = timeOf(year, month, 1)
  local start = first - (weekdayOf(first) - 1) * DAY_SECONDS
  local weeks = {}
  local time = start
  -- Always six weeks, so the card keeps one size while you move between months.
  for _ = 1, 6 do
    local week = { week = tonumber(os.date("%V", time)), days = {} }
    for column = 1, 7 do
      local date = os.date("*t", time)
      week.days[column] = {
        day = date.day,
        inMonth = date.month == month,
        weekend = column >= 6,
        today = date.year == today.year and date.month == today.month and date.day == today.day,
      }
      time = time + DAY_SECONDS
    end
    weeks[#weeks + 1] = week
  end
  return { title = os.date("%B %Y", first), weeks = weeks }
end

local STYLE = [[
  body { padding: 16px 18px; }
  .head { display: flex; justify-content: space-between; align-items: baseline; padding: 2px 4px 14px; }
  .title { font-size: 17px; }
  .nav span { color: #7a7a7a; padding: 0 6px; cursor: default; }
  .nav span:hover { color: #fff; }
  table { border-collapse: separate; border-spacing: 4px; width: 100%; font-family: "JetBrainsMono Nerd Font Mono", monospace; }
  th { color: #7a7a7a; font-weight: normal; font-size: 13px; height: 24px; text-align: center; }
  th.week, td.week { color: #4a4a4a; font-size: 12px; width: 26px; }
  td { text-align: center; height: 34px; border-radius: 4px; color: #e6e6e6; }
  td.out { color: #3a3a3a; }
  td.weekend { color: #9a9a9a; }
  td.today { background: #fff; color: #000; }
  .foot { border-top: 1px solid #2a2a2a; margin-top: 10px; padding: 10px 4px 0; color: #7a7a7a;
    display: flex; justify-content: space-between; font-size: 13px; }
  .foot b { color: #fff; font-weight: normal; }
]]

local SCRIPT = [[
  const send = (type, id) => window.webkit.messageHandlers.omv.postMessage({ type, id: id || "" });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") send("close");
    else if (event.key === "ArrowLeft") send("shift", "-1");
    else if (event.key === "ArrowRight") send("shift", "1");
    else if (event.key === "t" || event.key === "T") send("today");
  });
  document.querySelector(".prev").addEventListener("click", () => send("shift", "-1"));
  document.querySelector(".next").addEventListener("click", () => send("shift", "1"));
]]

local WEEKDAYS = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }

local function dayCell(day)
  local classes = {}
  if day.today then
    classes[1] = "today"
  elseif not day.inMonth then
    classes[1] = "out"
  elseif day.weekend then
    classes[1] = "weekend"
  end
  return "<td class=\"" .. table.concat(classes, " ") .. "\">" .. day.day .. "</td>"
end

local function grid(model)
  local header = { "<tr><th class=week>wk</th>" }
  for _, name in ipairs(WEEKDAYS) do header[#header + 1] = "<th>" .. name .. "</th>" end
  local rows = { table.concat(header) .. "</tr>" }
  for _, week in ipairs(model.weeks) do
    local cells = { "<tr><td class=week>" .. week.week .. "</td>" }
    for _, day in ipairs(week.days) do cells[#cells + 1] = dayCell(day) end
    rows[#rows + 1] = table.concat(cells) .. "</tr>"
  end
  return "<table>" .. table.concat(rows) .. "</table>"
end

function calendar.html(model, today)
  local now = timeOf(today.year, today.month, today.day)
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. STYLE .. "</style><body>"
    .. "<div class=head><span class=title>" .. card.escape(model.title) .. "</span>"
    .. "<span class=nav><span class=prev>‹</span><span class=next>›</span></span></div>"
    .. grid(model)
    .. "<div class=foot><span><b>" .. os.date("%A", now) .. "</b>, " .. tonumber(os.date("%d", now)) .. " " .. os.date("%B", now) .. "</span>"
    .. "<span>week " .. tonumber(os.date("%V", now)) .. "</span></div>"
    .. "<script>" .. SCRIPT .. "</script></body>"
end

return calendar
