-- The weather bar item and card. init.lua finds the Mac's location, fetches weather.url
-- from Open-Meteo and decodes the JSON; this turns it into a reading, the bar's label and
-- the card's HTML. Escape or a click elsewhere closes the card.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = require("card")

local weather = {}

local DASH = "—"
local FORECAST_DAYS = 3

weather.WIDTH = 500
weather.HEIGHT = 190
weather.PROBLEM_HEIGHT = 120

local WEEKDAYS = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY" }

-- WMO weather codes, as Open-Meteo reports them. Clear and partly cloudy have a night icon.
local ICONS = {
  clear = { day = "󰖙", night = "󰖔" },
  partly = { day = "󰖕", night = "󰼱" },
  cloudy = "󰖐",
  fog = "󰖑",
  drizzle = "󰖗",
  rain = "󰖖",
  snow = "󰖘",
  thunder = "󰖓",
}

local function kindOf(code)
  if code == 0 then return "clear" end
  if code == 1 or code == 2 then return "partly" end
  if code == 45 or code == 48 then return "fog" end
  if code >= 51 and code <= 57 then return "drizzle" end
  if (code >= 61 and code <= 67) or (code >= 80 and code <= 82) then return "rain" end
  if (code >= 71 and code <= 77) or code == 85 or code == 86 then return "snow" end
  if code >= 95 and code <= 99 then return "thunder" end
  return "cloudy"
end

function weather.icon(code, isDay)
  local icon = ICONS[kindOf(tonumber(code) or -1)]
  if type(icon) == "table" then return isDay and icon.day or icon.night end
  return icon
end

-- Rounds half away from zero, and never gives -0.
local function round(value)
  local rounded = value >= 0 and math.floor(value + 0.5) or -math.floor(-value + 0.5)
  return rounded == 0 and 0 or rounded
end

local function weekday(date)
  local year, month, day = date:match("^(%d+)-(%d+)-(%d+)$")
  if not year then return DASH end
  local time = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 })
  return WEEKDAYS[os.date("*t", time).wday]
end

-- The days after today, as many as the answer has, up to three.
local function forecast(daily)
  if type(daily) ~= "table" or type(daily.time) ~= "table" then return {} end
  local days = {}
  for index = 2, math.min(#daily.time, FORECAST_DAYS + 1) do
    local high, low = daily.temperature_2m_max and daily.temperature_2m_max[index], daily.temperature_2m_min and daily.temperature_2m_min[index]
    days[#days + 1] = {
      name = weekday(daily.time[index]),
      icon = weather.icon(daily.weather_code and daily.weather_code[index], true),
      high = high and round(high),
      low = low and round(low),
    }
  end
  return days
end

-- data is Open-Meteo's decoded answer. Gives nil when it has no current weather.
function weather.reading(data)
  if type(data) ~= "table" or type(data.current) ~= "table" then return nil end
  local current = data.current
  if type(current.temperature_2m) ~= "number" then return nil end
  return {
    temp = round(current.temperature_2m),
    feels = current.apparent_temperature and round(current.apparent_temperature),
    wind = current.wind_speed_10m and round(current.wind_speed_10m),
    humidity = current.relative_humidity_2m and round(current.relative_humidity_2m),
    icon = weather.icon(current.weather_code, current.is_day == 1),
    days = forecast(data.daily),
  }
end

function weather.url(latitude, longitude)
  return "https://api.open-meteo.com/v1/forecast?latitude=" .. latitude .. "&longitude=" .. longitude
    .. "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
    .. "&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=" .. (FORECAST_DAYS + 1)
end

function weather.barLabel(reading)
  return reading.temp .. "°"
end

local STYLE = [[
  body { padding: 26px 30px 22px; display: block; }
  .now { display: flex; align-items: center; }
  .now .icon { font-size: 64px; width: 84px; }
  .now .temp { font: 72px/1 "JetBrainsMono Nerd Font Mono", monospace; }
  .now .unit { font-size: 26px; align-self: flex-start; margin: 4px 0 0 4px; }
  .facts { margin-left: auto; width: 230px; }
  .place { color: #bdbdbd; letter-spacing: 2px; font-size: 15px; margin-bottom: 16px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .stats { display: flex; justify-content: space-between; }
  .stats .name { color: #7a7a7a; font-size: 13px; letter-spacing: 1px; margin-bottom: 6px; }
  .stats .value { font-size: 17px; white-space: nowrap; }
  .days { display: flex; justify-content: space-around; border-top: 1px solid #2a2a2a; margin-top: 22px; padding-top: 16px; }
  .day { display: flex; align-items: center; gap: 12px; }
  .day .icon { font-size: 28px; }
  .day .name { color: #7a7a7a; font-size: 13px; letter-spacing: 1px; }
  .day .low { color: #7a7a7a; }
  .problem { color: #bdbdbd; padding: 10px 0; }
]]

local SCRIPT = [[
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") window.webkit.messageHandlers.omv.postMessage({ type: "close", id: "" });
  });
]]

local function degrees(value, unit)
  if not value then return DASH end
  return value .. "°" .. (unit or "")
end

local function stat(name, value)
  return "<div><div class=name>" .. name .. "</div><div class=value>" .. card.escape(value) .. "</div></div>"
end

local function dayHtml(day)
  return "<div class=day><span class=icon>" .. day.icon .. "</span><div><div class=name>" .. card.escape(day.name) .. "</div>"
    .. "<div>" .. degrees(day.high) .. " <span class=low>" .. degrees(day.low) .. "</span></div></div></div>"
end

local function page(body)
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. STYLE .. "</style><body>"
    .. body .. "<script>" .. SCRIPT .. "</script></body>"
end

-- reading is weather.reading's result or nil; problem says why there is none.
function weather.html(reading, city, problem)
  local place = "<div class=place>󰍎 " .. card.escape(city and city:upper() or DASH) .. "</div>"
  if not reading then
    return page(place .. "<div class=problem>" .. card.escape(problem or "Looking up the weather…") .. "</div>")
  end
  local days = {}
  for _, day in ipairs(reading.days) do days[#days + 1] = dayHtml(day) end
  return page("<div class=now><span class=icon>" .. reading.icon .. "</span>"
    .. "<span class=temp>" .. reading.temp .. "</span><span class=unit>°C</span>"
    .. "<div class=facts>" .. place .. "<div class=stats>"
    .. stat("FEELS", degrees(reading.feels, "C"))
    .. stat("WIND", reading.wind and (reading.wind .. " km/h") or DASH)
    .. stat("HUMID", reading.humidity and (reading.humidity .. "%") or DASH)
    .. "</div></div></div>"
    .. (#days > 0 and ("<div class=days>" .. table.concat(days) .. "</div>") or ""))
end

function weather.height(reading)
  if not reading then return weather.PROBLEM_HEIGHT end
  return #reading.days > 0 and weather.HEIGHT or weather.HEIGHT - 70
end

return weather
