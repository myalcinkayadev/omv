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

local SKIES = {
  clear = "Clear", partly = "Partly cloudy", cloudy = "Cloudy", fog = "Fog", drizzle = "Drizzle",
  rain = "Rain", snow = "Snow", thunder = "Thunderstorm",
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

-- The sky in words, from a WMO code.
function weather.sky(code)
  return SKIES[kindOf(tonumber(code) or -1)]
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

-- Minutes since the epoch for a local ISO time, to measure between two of them.
local function minutes(time)
  local year, month, day, hour, minute = tostring(time):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
  if not year then return nil end
  return os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day),
    hour = tonumber(hour), min = tonumber(minute) }) / 60
end

-- An hour is named for when it starts; the first one, which holds now, is NOW.
local function hourLabel(endTime, first)
  if first then return "NOW" end
  local hour = tonumber(endTime:match("T(%d+):"))
  return hour and string.format("%02d", (hour - 1) % 24) or DASH
end

local function number(list, index)
  local value = type(list) == "table" and list[index] or nil
  return type(value) == "number" and value or nil
end

-- Open-Meteo gives rain and sky over the hour before each time, and temperature and UV at
-- it, so an hour takes its rain and sky from the time at its end and its temperature and
-- UV from the one at its start. The first hour starts now.
local function hourAt(hourly, index, first, now)
  local code = number(hourly.weather_code, index)
  local temperature, uv = number(hourly.temperature_2m, index - 1), number(hourly.uv_index, index - 1)
  return {
    label = hourLabel(hourly.time[index], first),
    from = first and now or hourly.time[index - 1],
    to = hourly.time[index],
    rain = number(hourly.precipitation, index) or 0,
    temp = temperature and round(temperature),
    uv = uv and round(uv),
    kind = code and kindOf(code) or "cloudy",
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
    if time > now then upcoming[#upcoming + 1] = hourAt(hourly, index, #upcoming == 0, now) end
  end
  return upcoming
end

local function daily(data, field, index)
  local list = type(data) == "table" and data[field]
  return type(list) == "table" and list[index] or nil
end

-- The dark spans around now: before today's sunrise, then from each sunset to the next
-- sunrise. A span's open end runs off the hours.
local function nights(days)
  if not (daily(days, "sunrise", 1) and daily(days, "sunset", 1)) then return {} end
  local spans = { { to = days.sunrise[1] } }
  for day = 1, #days.sunset do spans[#spans + 1] = { from = days.sunset[day], to = daily(days, "sunrise", day + 1) } end
  return spans
end

-- The next sunrise or sunset after now, as { name, minutes away }.
local function nextSun(days, now)
  local events = {}
  for day = 1, 2 do
    events[#events + 1] = { name = "Sunrise", time = daily(days, "sunrise", day) }
    events[#events + 1] = { name = "Sunset", time = daily(days, "sunset", day) }
  end
  table.sort(events, function(a, b) return tostring(a.time) < tostring(b.time) end)
  for _, event in ipairs(events) do
    if event.time and event.time > now then
      return { name = event.name, left = math.floor(minutes(event.time) - minutes(now) + 0.5) }
    end
  end
  return nil
end

-- data is Open-Meteo's decoded answer. Gives nil when it has no current weather.
function weather.reading(data)
  if type(data) ~= "table" or type(data.current) ~= "table" then return nil end
  local current = data.current
  if type(current.temperature_2m) ~= "number" then return nil end
  local high, low = daily(data.daily, "temperature_2m_max", 1), daily(data.daily, "temperature_2m_min", 1)
  return {
    temp = round(current.temperature_2m),
    feels = current.apparent_temperature and round(current.apparent_temperature),
    wind = current.wind_speed_10m and round(current.wind_speed_10m),
    windFrom = current.wind_direction_10m and round(current.wind_direction_10m),
    humidity = current.relative_humidity_2m and round(current.relative_humidity_2m),
    uv = current.uv_index and round(current.uv_index),
    icon = weather.icon(current.weather_code, current.is_day == 1),
    sky = weather.sky(current.weather_code),
    high = high and round(high),
    low = low and round(low),
    days = forecast(data.daily),
    hours = hours(data.hourly, current.time),
    time = clock(current.time),
    sunrise = clock(daily(data.daily, "sunrise", 1)),
    sunset = clock(daily(data.daily, "sunset", 1)),
    nights = nights(data.daily),
    nextSun = type(current.time) == "string" and nextSun(data.daily, current.time) or nil,
    dayLength = minutes(daily(data.daily, "sunset", 1)) and minutes(daily(data.daily, "sunrise", 1))
      and minutes(data.daily.sunset[1]) - minutes(data.daily.sunrise[1]) or nil,
    sinceSunrise = type(current.time) == "string" and minutes(daily(data.daily, "sunrise", 1))
      and minutes(current.time) - minutes(data.daily.sunrise[1]) or nil,
  }
end

function weather.url(latitude, longitude)
  return "https://api.open-meteo.com/v1/forecast?latitude=" .. latitude .. "&longitude=" .. longitude
    .. "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_direction_10m,uv_index,weather_code,is_day"
    .. "&hourly=precipitation,temperature_2m,weather_code,is_day,uv_index"
    .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto&forecast_days=" .. (FORECAST_DAYS + 1)
end

function weather.barLabel(reading)
  return reading.temp .. "°"
end

-- Rain by strength, from millimetres an hour, on the usual scale. A trace is no rain.
function weather.strength(mm)
  if not mm or mm < 0.3 then return nil end
  if mm >= 7.6 then return "heavy" end
  if mm >= 2.5 then return "moderate" end
  return "light"
end

-- UV on the WHO scale.
function weather.uvLevel(uv)
  if uv <= 2 then return "low" end
  if uv <= 5 then return "moderate" end
  if uv <= 7 then return "high" end
  if uv <= 10 then return "very high" end
  return "extreme"
end

local function startClock(hour)
  return hour.label == "NOW" and "now" or hour.label .. ":00"
end

-- One line on what matters most in the next hours: rain, when it comes, or else where the
-- temperature goes, and fog setting in.
function weather.summary(reading)
  local list = reading.hours
  if #list == 0 then return nil end
  local first, last, peak
  for index, hour in ipairs(list) do
    if weather.strength(hour.rain) then
      first, last = first or index, index
      if not peak or hour.rain > list[peak].rain then peak = index end
    end
  end
  if first then
    return "Rain from " .. startClock(list[first]) .. " to " .. (clock(list[last].to) or DASH)
      .. ", heaviest at " .. startClock(list[peak]) .. "."
  end
  local low, high
  for index, hour in ipairs(list) do
    if hour.temp and (not low or hour.temp < list[low].temp) then low = index end
    if hour.temp and (not high or hour.temp > list[high].temp) then high = index end
  end
  local text = "Dry. Around " .. reading.temp .. "° for the next " .. #list .. " hours"
  if low and list[low].temp <= reading.temp - 3 then
    text = "Dry. Cooling to " .. list[low].temp .. "° by " .. startClock(list[low])
  elseif high and list[high].temp >= reading.temp + 3 then
    text = "Dry. Warming to " .. list[high].temp .. "° by " .. startClock(list[high])
  end
  for index = 2, #list do
    if list[index].kind == "fog" and list[1].kind ~= "fog" then
      text = text .. ", fog from " .. startClock(list[index])
      break
    end
  end
  return text .. "."
end

-- The chart's frame, in the card's pixels: the line runs from TOP to BOTTOM, and the rain
-- row needs EXTRA below it.
local CHART = { width = 436, top = 66, bottom = 128, dry = 162, wet = 184 }
local SHADES = { clear = 0.06, partly = 0.10, cloudy = 0.22, fog = 0.22, drizzle = 0.36, snow = 0.36, rain = 0.5, thunder = 0.5 }
local RANK = { light = 1, moderate = 2, heavy = 3 }
local LEVEL = { light = 0.35, moderate = 0.65, heavy = 1 }

local function px(value)
  return (string.format("%.1f", value):gsub("%.0$", ""))
end

local function anyRain(list)
  for _, hour in ipairs(list) do
    if weather.strength(hour.rain) then return true end
  end
  return false
end

-- Where a time falls along the hours, in pixels: within an hour, by its share of it.
local function placer(list, x)
  return function(time)
    if time < list[1].from then return 0 end
    for index, hour in ipairs(list) do
      if time >= hour.from and time < hour.to then
        local from, to, at = minutes(hour.from), minutes(hour.to), minutes(time)
        local share = (from and to and at and to > from) and (at - from) / (to - from) or 0
        local nextX = index < #list and x(index + 1) or CHART.width
        return x(index) + share * (nextX - x(index))
      end
    end
    return CHART.width
  end
end

local function nightHtml(reading, list, x, bottom)
  local at, parts = placer(list, x), {}
  local first, last = list[1].from, list[#list].to
  for _, span in ipairs(reading.nights) do
    local starts, ends = span.from, span.to
    if not (starts and starts >= last) and not (ends and ends <= first) then
      local a, b = starts and at(starts) or 0, ends and at(ends) or CHART.width
      if b > a then
        parts[#parts + 1] = '<rect class=night x="' .. px(a) .. '" y="0" width="' .. px(b - a) .. '" height="' .. bottom
          .. '" fill="#fff" fill-opacity="0.045"/>'
      end
      if starts and starts >= first then
        parts[#parts + 1] = '<line class=sunset x1="' .. px(a) .. '" x2="' .. px(a) .. '" y1="0" y2="' .. bottom
          .. '" stroke="#7a7a7a" stroke-dasharray="2 3"/>'
      end
    end
  end
  return table.concat(parts)
end

local function chartHtml(reading)
  local list, n = reading.hours, #reading.hours
  local wet = anyRain(list)
  local height, base = wet and CHART.wet or CHART.dry, CHART.bottom + 8
  local step = n > 1 and (CHART.width - 28) / (n - 1) or 0
  local function x(index) return n > 1 and 14 + (index - 1) * step or CHART.width / 2 end
  local high, low
  for _, hour in ipairs(list) do
    if hour.temp then high, low = math.max(high or hour.temp, hour.temp), math.min(low or hour.temp, hour.temp) end
  end
  local function y(temp)
    if high == low then return (CHART.top + CHART.bottom) / 2 end
    return CHART.bottom - (temp - low) / (high - low) * (CHART.bottom - CHART.top)
  end

  local svg, spans, line, shown, runs = {}, {}, {}, nil, {}
  for index, hour in ipairs(list) do
    local left, right = math.max(0, x(index) - step / 2), math.min(CHART.width, x(index) + step / 2)
    svg[#svg + 1] = '<rect class=band x="' .. px(left) .. '" y="26" width="' .. px(right - left) .. '" height="5" fill="#fff" fill-opacity="'
      .. SHADES[hour.kind] .. '" style="--d:' .. (200 + index * 30) .. 'ms"/>'
    local kind = weather.strength(hour.rain)
    if kind then
      local tall = LEVEL[kind] * 70
      svg[#svg + 1] = '<rect class=wet x="' .. px(x(index) - step / 2 + 2) .. '" y="' .. px(base - tall) .. '" width="' .. px(step - 4)
        .. '" height="' .. px(tall) .. '" fill="#bdbdbd" fill-opacity="' .. px(0.12 + LEVEL[kind] * 0.2) .. '" style="--d:'
        .. (500 + index * 40) .. 'ms"/>'
      local run = runs[#runs]
      if run and run.kind == kind and run.to == index - 1 then run.to = index else runs[#runs + 1] = { kind = kind, from = index, to = index } end
    end
    if hour.temp then
      line[#line + 1] = (#line == 0 and "M" or "L") .. px(x(index)) .. " " .. px(y(hour.temp))
      spans[#spans + 1] = '<span class=lbl style="--d:' .. (250 + index * 50) .. 'ms;left:' .. px(x(index)) .. 'px;top:' .. px(y(hour.temp) - 8)
        .. 'px">' .. hour.temp .. "°</span>"
    end
    if hour.icon ~= shown then
      shown = hour.icon
      spans[#spans + 1] = '<span class=sky style="--d:' .. (150 + index * 40) .. 'ms;left:' .. px(x(index)) .. 'px">' .. hour.icon .. "</span>"
    end
    spans[#spans + 1] = '<span class=tm style="left:' .. px(x(index)) .. 'px">' .. hour.label .. "</span>"
  end
  local strongest
  for _, run in ipairs(runs) do
    if not strongest or RANK[run.kind] > RANK[strongest.kind] then strongest = run end
  end
  if strongest then
    spans[#spans + 1] = '<span class=rain style="left:' .. px((x(strongest.from) + x(strongest.to)) / 2) .. 'px;top:' .. (base + 6)
      .. 'px">' .. strongest.kind .. "</span>"
  end
  local readout = {}
  for _, hour in ipairs(list) do
    readout[#readout + 1] = "[" .. card.jsString(hour.label == "NOW" and "Now" or hour.label .. ":00") .. ","
      .. card.jsString(hour.temp and (hour.temp .. "°") or DASH) .. "," .. card.jsString(SKIES[hour.kind] or "") .. ","
      .. card.jsString(weather.strength(hour.rain) and (weather.strength(hour.rain) .. " rain") or "dry") .. ","
      .. card.jsString(hour.uv and ("UV " .. hour.uv) or "") .. "]"
  end
  local path = table.concat(line, " ")
  local first = list[1].temp and { x(1), y(list[1].temp) }
  return '<div class=hours><div class=curve tabindex=0 style="height:' .. height .. 'px" data-step="' .. px(step) .. '">'
    .. '<svg viewBox="0 0 ' .. CHART.width .. " " .. height .. '" preserveAspectRatio="none" aria-hidden="true">'
    .. nightHtml(reading, list, x, base) .. table.concat(svg)
    .. (#line > 0 and ('<path class=area d="' .. path .. " L" .. px(x(n)) .. " " .. base .. " L" .. px(x(1)) .. " " .. base
      .. ' Z" fill="#fff" fill-opacity="0.04"/><path class=line d="' .. path .. '" pathLength="1" fill="none" stroke="#fff"'
      .. ' stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>') or "")
    .. (first and ('<circle class=pulse cx="' .. px(first[1]) .. '" cy="' .. px(first[2]) .. '" r="4" fill="#fff"/><circle cx="'
      .. px(first[1]) .. '" cy="' .. px(first[2]) .. '" r="4" fill="#fff"/>') or "")
    .. "</svg>" .. table.concat(spans) .. "<div class=cursor hidden></div><div class=tip hidden></div></div></div>"
    .. "<script>window.omvHours = [" .. table.concat(readout, ",") .. "];</script>"
end

local STYLE = [[
  body { padding: 26px 30px 22px; display: block; }
  .place { color: #bdbdbd; letter-spacing: 1px; font-size: 14px; margin-bottom: 14px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .problem { color: #bdbdbd; padding: 10px 0; }
  .top { display: flex; align-items: flex-end; justify-content: space-between; }
  .now { display: flex; align-items: center; padding-bottom: 31px; }
  .now:only-child { padding-bottom: 0; }
  .now .icon { font-size: 52px; width: 66px; }
  .now .temp { font: 64px/1 "JetBrainsMono Nerd Font Mono", monospace; }
  .now .unit { font-size: 22px; align-self: flex-start; margin: 2px 0 0 2px; }
  .arc { width: 132px; text-align: center; }
  .arc svg { display: block; overflow: visible; }
  .arc .ends { display: flex; justify-content: space-between; font-size: 12px; color: #bdbdbd; margin-top: 4px; }
  .arc .until { font-size: 12px; color: #7a7a7a; letter-spacing: .5px; margin-top: 2px; }
  .cond { margin-top: 12px; font-size: 13px; color: #7a7a7a; }
  .cond .word { font-size: 17px; color: #fff; }
  .details { display: grid; grid-template-columns: repeat(3, 1fr); border-top: 1px solid #2a2a2a; margin-top: 18px; padding-top: 14px; }
  .details .name { color: #7a7a7a; font-size: 12px; letter-spacing: 1px; margin-bottom: 5px; }
  .details .value { font-size: 16px; white-space: nowrap; }
  .details .level { font-size: 12px; color: #7a7a7a; letter-spacing: .5px; }
  .arrow { width: 12px; height: 12px; vertical-align: -1px; margin-left: 6px; }
  .summary { margin-top: 18px; font-size: 15px; }
  .hours { border-top: 1px solid #2a2a2a; margin-top: 18px; padding-top: 14px; }
  .curve { position: relative; outline: none; cursor: crosshair; }
  .curve svg { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible; }
  .curve .lbl { position: absolute; transform: translate(-50%, -100%); font-size: 12px; white-space: nowrap; }
  .curve .sky { position: absolute; top: 0; transform: translateX(-50%); font-size: 18px; }
  .curve .tm { position: absolute; bottom: 0; transform: translateX(-50%); color: #7a7a7a; font-size: 11px; }
  .curve .rain { position: absolute; transform: translateX(-50%); font-size: 12px; color: #bdbdbd; letter-spacing: 1px; }
  .cursor { position: absolute; top: 0; bottom: 30px; width: 1px; background: #bdbdbd; pointer-events: none; }
  .tip { position: absolute; top: 36px; transform: translateX(-50%); background: #000; border: 1px solid #8d8d8d;
    padding: 6px 9px; font-size: 12px; line-height: 1.5; color: #bdbdbd; white-space: nowrap; pointer-events: none; }
  .tip b { color: #fff; font-weight: normal; }
  .days { border-top: 1px solid #2a2a2a; margin-top: 18px; padding-top: 12px; display: grid; gap: 8px; }
  .day { display: grid; grid-template-columns: 110px 28px 40px 1fr 40px; gap: 10px; align-items: center; }
  .day .name { color: #7a7a7a; font-size: 13px; letter-spacing: 1px; }
  .day .icon { font-size: 20px; }
  .day .low { color: #7a7a7a; text-align: right; }
  .range { height: 4px; background: #2a2a2a; border-radius: 2px; position: relative; }
  .range i { position: absolute; top: 0; bottom: 0; background: #bdbdbd; border-radius: 2px; }

  @keyframes draw { from { stroke-dashoffset: 1; } to { stroke-dashoffset: 0; } }
  @keyframes rise { from { opacity: 0; transform: var(--t0) translateY(6px); } }
  @keyframes fadein { from { opacity: 0; } }
  @keyframes grow { from { transform: scaleY(0); } }
  @keyframes widen { from { transform: scaleX(0); } }
  @keyframes pulse { from { transform: scale(1); opacity: .6; } to { transform: scale(3.2); opacity: 0; } }
  .line { stroke-dasharray: 1; animation: draw 1100ms cubic-bezier(.3, .7, .2, 1) both; }
  .band, .area, .fade, .now, .cond, .details, .summary, .day { animation: fadein 500ms ease-out both; animation-delay: var(--d, 0ms); }
  .wet { transform-box: fill-box; transform-origin: bottom; animation: grow 550ms cubic-bezier(.2, .8, .2, 1) both; animation-delay: var(--d, 0ms); }
  .range i { transform-origin: left; animation: widen 700ms cubic-bezier(.2, .8, .2, 1) both; animation-delay: var(--d, 0ms); }
  .pulse { transform-box: fill-box; transform-origin: center; animation: pulse 1400ms ease-out 1100ms 2 both; }
  .curve .lbl { --t0: translate(-50%, -100%); animation: rise 450ms ease-out both; animation-delay: var(--d, 0ms); }
  .curve .sky { --t0: translateX(-50%); animation: rise 450ms ease-out both; animation-delay: var(--d, 0ms); }
  .summary { --d: 120ms; }
  @media (prefers-reduced-motion: reduce) { * { animation: none !important; } .line { stroke-dasharray: none; } }
]]

-- Escape closes. Over the hours, the pointer, or Left and Right, read out one hour.
local SCRIPT = [[
  const curve = document.querySelector(".curve");
  let at = -1;
  function readout(index) {
    const hours = window.omvHours || [];
    if (!curve || !hours.length) return;
    at = Math.max(0, Math.min(hours.length - 1, index));
    const step = Number(curve.dataset.step), x = hours.length > 1 ? 14 + at * step : curve.clientWidth / 2;
    const [time, temp, sky, rain, uv] = hours[at];
    const tip = curve.querySelector(".tip"), cursor = curve.querySelector(".cursor");
    tip.innerHTML = "<b>" + time + "</b> · " + temp + " · " + sky + "<br>" + rain + (uv ? " · " + uv : "");
    tip.style.left = Math.min(Math.max(x, 80), curve.clientWidth - 80) + "px";
    cursor.style.left = x + "px";
    tip.hidden = cursor.hidden = false;
  }
  function hide() {
    if (!curve) return;
    curve.querySelector(".tip").hidden = curve.querySelector(".cursor").hidden = true;
  }
  if (curve) {
    curve.addEventListener("mousemove", (event) => {
      const box = curve.getBoundingClientRect(), step = Number(curve.dataset.step) || 1;
      readout(Math.round((event.clientX - box.left - 14) / step));
    });
    curve.addEventListener("mouseleave", hide);
  }
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") return window.webkit.messageHandlers.omv.postMessage({ type: "close", id: "" });
    if (event.key === "ArrowRight") readout(at + 1);
    else if (event.key === "ArrowLeft") readout(at < 0 ? 0 : at - 1);
  });
]]

local function degrees(value, unit)
  if not value then return DASH end
  return value .. "°" .. (unit or "")
end

-- Where the sun is between sunrise and sunset, and how long until the next of them.
local function arcHtml(reading)
  if not (reading.sunrise and reading.sunset) then return "" end
  local share = reading.dayLength and reading.sinceSunrise and reading.dayLength > 0
    and reading.sinceSunrise / reading.dayLength or -1
  local day = share >= 0 and share < 1
  local cx, cy, r = 66, 56, 50
  local angle = math.pi * (1 - math.max(0, math.min(1, share)))
  local sx, sy = cx + r * math.cos(angle), cy - r * math.sin(angle)
  local untilText = ""
  if reading.nextSun then
    untilText = string.format("%s in %dh %02dm", reading.nextSun.name, math.floor(reading.nextSun.left / 60), reading.nextSun.left % 60)
  end
  return "<div class=arc>"
    .. '<svg viewBox="0 0 132 60" width="132" height="60" aria-hidden="true">'
    .. '<line x1="0" x2="132" y1="' .. cy .. '" y2="' .. cy .. '" stroke="#2a2a2a"/>'
    .. '<path d="M ' .. (cx - r) .. " " .. cy .. " A " .. r .. " " .. r .. " 0 0 1 " .. (cx + r) .. " " .. cy
    .. '" fill="none" stroke="#3a3a3a" stroke-width="1.5" stroke-dasharray="3 4"/>'
    .. (day and ('<path class=line d="M ' .. (cx - r) .. " " .. cy .. " A " .. r .. " " .. r .. " 0 0 1 " .. px(sx) .. " " .. px(sy)
      .. '" pathLength="1" fill="none" stroke="#bdbdbd" stroke-width="2"/>') or "")
    .. '<circle class=fade cx="' .. px(day and sx or cx - r) .. '" cy="' .. px(day and sy or cy) .. '" r="5" fill="#fff"/></svg>'
    .. "<div class=ends><span>" .. reading.sunrise .. "</span><span>" .. reading.sunset .. "</span></div>"
    .. "<div class=until>" .. untilText .. "</div></div>"
end

local function arrowHtml(from)
  if not from then return "" end
  return '<svg class=arrow viewBox="0 0 12 12" style="transform:rotate(' .. ((from + 180) % 360) .. 'deg)">'
    .. '<path d="M6 1 L10 7 H7 V11 H5 V7 H2 Z" fill="currentColor"/></svg>'
end

local function cell(name, value)
  return "<div class=cell><div class=name>" .. name .. "</div><div class=value>" .. value .. "</div></div>"
end

-- Each day's low and high on one scale, from the coldest low to the warmest high.
local function daysHtml(days)
  if #days == 0 then return "" end
  local coldest, warmest
  for _, day in ipairs(days) do
    if day.low then coldest = math.min(coldest or day.low, day.low) end
    if day.high then warmest = math.max(warmest or day.high, day.high) end
  end
  local function share(value)
    if not (value and coldest and warmest) or warmest == coldest then return 0 end
    return (value - coldest) / (warmest - coldest) * 100
  end
  local rows = {}
  for index, day in ipairs(days) do
    rows[#rows + 1] = "<div class=day><span class=name>" .. card.escape(day.name) .. "</span><span class=icon>" .. day.icon .. "</span>"
      .. "<span class=low>" .. degrees(day.low) .. "</span><div class=range><i style=\"--d:" .. (600 + index * 90) .. "ms;left:"
      .. px(share(day.low)) .. "%;right:" .. px(100 - share(day.high)) .. '%"></i></div><span>' .. degrees(day.high) .. "</span></div>"
  end
  return "<div class=days>" .. table.concat(rows) .. "</div>"
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
  local highLow = reading.high and reading.low and (" · H " .. degrees(reading.high) .. " L " .. degrees(reading.low)) or ""
  local uv = reading.uv and (reading.uv .. " <span class=level>" .. weather.uvLevel(reading.uv) .. "</span>") or DASH
  local summary = weather.summary(reading)
  return page(place
    .. "<div class=top><div class=now><span class=icon>" .. reading.icon .. "</span><span class=temp>" .. reading.temp
    .. "</span><span class=unit>°C</span></div>" .. arcHtml(reading) .. "</div>"
    .. "<div class=cond><span class=word>" .. card.escape(reading.sky) .. "</span> · Feels " .. degrees(reading.feels) .. highLow .. "</div>"
    .. "<div class=details>" .. cell("WIND", (reading.wind and (reading.wind .. " km/h") or DASH) .. arrowHtml(reading.windFrom))
    .. cell("HUMIDITY", reading.humidity and (reading.humidity .. "%") or DASH) .. cell("UV", uv) .. "</div>"
    .. (summary and ("<div class=summary>" .. card.escape(summary) .. "</div>") or "")
    .. (#reading.hours > 0 and chartHtml(reading) or "")
    .. daysHtml(reading.days))
end

-- The card's height, measured from the page: the header, the summary, the hours, which
-- take a row more when it rains, and a row a day.
local HEIGHTS = { header = 293, summary = 38, hours = 33, days = 23, day = 34 }

function weather.height(reading)
  if not reading then return weather.PROBLEM_HEIGHT end
  local height = HEIGHTS.header + (weather.summary(reading) and HEIGHTS.summary or 0)
  if #reading.hours > 0 then height = height + HEIGHTS.hours + (anyRain(reading.hours) and CHART.wet or CHART.dry) end
  if #reading.days > 0 then height = height + HEIGHTS.days + #reading.days * HEIGHTS.day end
  return height
end

return weather
