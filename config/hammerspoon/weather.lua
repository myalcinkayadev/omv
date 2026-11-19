-- The weather bar item and card. init.lua finds the Mac's location, fetches weather.url
-- from Open-Meteo and decodes the JSON; this turns it into a reading, the bar's label and
-- the card's HTML. Escape or a click elsewhere closes the card.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = require("card")

local weather = {}

local DASH = "—"
local FORECAST_DAYS = 3
local FORECAST_HOURS = 12

weather.WIDTH = 500
weather.HEIGHT = 206
weather.HOURS_HEIGHT = 170
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

-- The "HH:MM" of an Open-Meteo local ISO time, or nil.
local function clock(time)
  return type(time) == "string" and time:match("T(%d+:%d+)") or nil
end

-- An hour is named for when it starts; the first one, which holds now, is NOW.
local function hourLabel(endTime, first)
  if first then return "NOW" end
  local hour = tonumber(endTime:match("T(%d+):"))
  return hour and string.format("%02d", (hour - 1) % 24) or DASH
end

-- Open-Meteo gives chance and sky over the hour before each time, and temperature at it,
-- so an hour takes its chance and icon from the time at its end and its temperature
-- from the one at its start.
local function hourAt(hourly, index, first)
  local chance = (hourly.precipitation_probability or {})[index]
  local temperature = (hourly.temperature_2m or {})[index - 1]
  local code = (hourly.weather_code or {})[index]
  return {
    label = hourLabel(hourly.time[index], first),
    chance = type(chance) == "number" and round(chance / 10) * 10 or nil,
    temp = type(temperature) == "number" and round(temperature) or nil,
    icon = code and weather.icon(code, (hourly.is_day or {})[index] == 1) or "",
  }
end

-- The next hours from now, up to twelve, past midnight if need be. Open-Meteo's times are
-- local ISO strings, so comparing them as text orders them.
local function hours(hourly, now)
  if type(hourly) ~= "table" or type(hourly.time) ~= "table" or type(now) ~= "string" then return {} end
  local upcoming = {}
  for index, time in ipairs(hourly.time) do
    if #upcoming == FORECAST_HOURS then break end
    if time > now then upcoming[#upcoming + 1] = hourAt(hourly, index, #upcoming == 0) end
  end
  return upcoming
end

local function today(daily, field)
  return type(daily) == "table" and type(daily[field]) == "table" and clock(daily[field][1]) or nil
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
    hours = hours(data.hourly, current.time),
    time = clock(current.time),
    sunrise = today(data.daily, "sunrise"),
    sunset = today(data.daily, "sunset"),
  }
end

function weather.url(latitude, longitude)
  return "https://api.open-meteo.com/v1/forecast?latitude=" .. latitude .. "&longitude=" .. longitude
    .. "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
    .. "&hourly=precipitation_probability,temperature_2m,weather_code,is_day"
    .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto&forecast_days=" .. (FORECAST_DAYS + 1)
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
  .hours { border-top: 1px solid #2a2a2a; margin-top: 22px; padding-top: 14px; }
  .hours .title { display: flex; justify-content: space-between; color: #7a7a7a; font-size: 13px;
    letter-spacing: 1px; margin-bottom: 8px; }
  .hours .columns { display: flex; justify-content: space-between; }
  .hour { width: 36px; display: flex; flex-direction: column; align-items: center; }
  .hour .icon { font-size: 18px; }
  .hour .temp { font-size: 13px; margin: 2px 0 4px; }
  .hour .chance { font-size: 12px; color: #bdbdbd; white-space: nowrap; }
  .hour .chance.dim { color: #5a5a5a; }
  .hour .track { height: 28px; width: 4px; display: flex; align-items: flex-end; margin: 4px 0; }
  .hour .bar { width: 4px; min-height: 1px; background: #bdbdbd; }
  .hour .time { color: #7a7a7a; font-size: 12px; }
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

local DIM_BELOW = 30

local function hourHtml(hour)
  local chance = hour.chance and (hour.chance .. "%") or DASH
  local dim = hour.chance and hour.chance < DIM_BELOW and " dim" or ""
  local bar = hour.chance and ("<div class=bar style=\"height:" .. hour.chance .. "%\"></div>") or ""
  return "<div class=hour><span class=icon>" .. hour.icon .. "</span><div class=temp>" .. degrees(hour.temp) .. "</div>"
    .. "<div class=\"chance" .. dim .. "\">" .. chance .. "</div><div class=track>" .. bar .. "</div>"
    .. "<div class=time>" .. hour.label .. "</div></div>"
end

local function sunHtml(reading)
  if not (reading.sunrise and reading.sunset) then return "" end
  return "<span>󰖜 " .. reading.sunrise .. "  󰖛 " .. reading.sunset .. "</span>"
end

local function hoursHtml(reading)
  if #reading.hours == 0 then return "" end
  local columns = {}
  for _, hour in ipairs(reading.hours) do columns[#columns + 1] = hourHtml(hour) end
  return "<div class=hours><div class=title><span>NEXT 12 HOURS · PRECIP %</span>" .. sunHtml(reading) .. "</div>"
    .. "<div class=columns>" .. table.concat(columns) .. "</div></div>"
end

local function page(body)
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. STYLE .. "</style><body>"
    .. body .. "<script>" .. SCRIPT .. "</script></body>"
end

-- reading is weather.reading's result or nil; problem says why there is none.
function weather.html(reading, city, problem)
  local stamp = reading and reading.time and (" · " .. reading.time) or ""
  local place = "<div class=place>󰍎 " .. card.escape(city and city:upper() or DASH) .. stamp .. "</div>"
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
    .. hoursHtml(reading)
    .. (#days > 0 and ("<div class=days>" .. table.concat(days) .. "</div>") or ""))
end

function weather.height(reading)
  if not reading then return weather.PROBLEM_HEIGHT end
  local height = #reading.days > 0 and weather.HEIGHT or weather.HEIGHT - 70
  return #reading.hours > 0 and height + weather.HOURS_HEIGHT or height
end

return weather
