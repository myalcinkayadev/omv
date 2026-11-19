-- Behavior of the weather bar item and card. Run through weather_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local weather = require("weather")

-- Two days of hours from midnight on 2026-11-08. Each hour's chance is its hour of the day,
-- its temperature that plus 0.4, its sky clear, and it is day from 07:00 to 16:00.
-- Index 21 is 20:00 and index 22 is 21:00 on the first day.
local function hourly()
  local times, chances, temperatures, codes, days = {}, {}, {}, {}, {}
  for index = 0, 47 do
    local hour = index % 24
    times[#times + 1] = string.format("2026-11-%02dT%02d:00", 8 + math.floor(index / 24), hour)
    chances[#chances + 1] = hour
    temperatures[#temperatures + 1] = hour + 0.4
    codes[#codes + 1] = 0
    days[#days + 1] = (hour >= 7 and hour < 17) and 1 or 0
  end
  return { time = times, precipitation_probability = chances, temperature_2m = temperatures, weather_code = codes, is_day = days }
end

-- Shaped like Open-Meteo's answer to weather.url, after JSON decoding.
local function response()
  return {
    current = {
      temperature_2m = 4.6, apparent_temperature = 0.8, relative_humidity_2m = 43,
      wind_speed_10m = 19.7, weather_code = 0, is_day = 0, time = "2026-11-08T20:30",
    },
    hourly = hourly(),
    daily = {
      time = { "2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11" },
      weather_code = { 3, 2, 73, 45 },
      temperature_2m_max = { 7, 8.2, 4.6, 11.4 },
      temperature_2m_min = { -2, -3.4, -1, 0.3 },
      sunrise = { "2026-11-08T07:12", "2026-11-09T07:13", "2026-11-10T07:14", "2026-11-11T07:15" },
      sunset = { "2026-11-08T16:48", "2026-11-09T16:47", "2026-11-10T16:46", "2026-11-11T16:45" },
    },
  }
end

local reading = weather.reading(response())
local page = check.visible(weather.html(reading, "Ankara"))

check.that("should round the temperature when it has a fraction", reading.temp == 5)
check.that("should show the temperature in °C on the card", check.contains(page, "5°C"))
check.that("should show feels-like on the card", check.contains(page, "1°C"))
check.that("should show wind in km/h on the card", check.contains(page, "20 km/h"))
check.that("should show humidity on the card", check.contains(page, "43%"))
check.that("should show the city uppercased on the card", check.contains(page, "ANKARA"))
check.that("should show a dash when the city is unknown", check.contains(check.visible(weather.html(reading, nil)), "—"))

check.that("should list three forecast days when four are given", #reading.days == 3)
check.that("should start the forecast tomorrow rather than today", reading.days[1].name == "MONDAY")
check.that("should name the third forecast day", reading.days[3].name == "WEDNESDAY")
check.that("should round each day's high", reading.days[1].high == 8)
check.that("should round each day's low", reading.days[1].low == -3)
check.that("should show each day's high and low on the card", check.contains(page, "8°") and check.contains(page, "-3°"))

check.that("should use the night icon when the sky is clear after dark", reading.icon == weather.icon(0, false))
check.that("should use different icons for a clear day and a clear night", weather.icon(0, true) ~= weather.icon(0, false))
check.that("should use the snow icon when the code is 73", reading.days[2].icon == weather.icon(71, true))
check.that("should use the fog icon when the code is 45", reading.days[3].icon == weather.icon(48, true))
check.that("should use the cloudy icon when the code is unknown", weather.icon(12345, true) == weather.icon(3, true))
check.that("should use the rain icon for showers", weather.icon(81, true) == weather.icon(63, true))

local short = response()
short.daily.time = { "2026-11-08", "2026-11-09" }
check.that("should list only the days it has when fewer are given", #weather.reading(short).days == 1)
local noDaily = response()
noDaily.daily = nil
check.that("should list no days when the forecast is missing", #weather.reading(noDaily).days == 0)
check.that("should still render when the forecast is missing", check.contains(check.visible(weather.html(weather.reading(noDaily), "Ankara")), "5°C"))
check.that("should give no reading when current weather is missing", weather.reading({ daily = response().daily }) == nil)
check.that("should give no reading when the answer is not a table", weather.reading(nil) == nil)

check.that("should show the problem when there is no reading",
  check.contains(check.visible(weather.html(nil, nil, "No connection")), "No connection"))

check.that("should label the bar with the rounded temperature", weather.barLabel(reading) == "5°")
check.that("should label the bar with a minus when below zero", weather.barLabel({ temp = -3 }) == "-3°")
check.that("should never label the bar -0°", weather.barLabel(weather.reading((function()
  local cold = response(); cold.current.temperature_2m = -0.2; return cold
end)())) == "0°")

local function withHourly(change)
  local data = response()
  change(data.hourly, data)
  return weather.reading(data)
end
local function cardOf(changed) return check.visible(weather.html(changed, "Ankara")) end

check.that("should list twelve hours when more are available", #reading.hours == 12)
check.that("should label the first hour NOW", reading.hours[1].label == "NOW")
check.that("should label each later hour by when it starts", reading.hours[2].label == "21")
check.that("should label the last of twelve hours by when it starts", reading.hours[12].label == "07")
check.that("should wrap the label past midnight", reading.hours[4].label == "23")
check.that("should take an hour's chance from the value at its end",
  withHourly(function(h) h.precipitation_probability[21] = 0; h.precipitation_probability[22] = 70 end).hours[1].chance == 70)
check.that("should take an hour's temperature from its start", reading.hours[1].temp == 20)
check.that("should take an hour's icon from the value at its end",
  withHourly(function(h) h.weather_code[22] = 61 end).hours[1].icon == weather.icon(61, false))
check.that("should round the chance down to the nearest ten",
  withHourly(function(h) h.precipitation_probability[22] = 44 end).hours[1].chance == 40)
check.that("should round the chance up to the nearest ten from halfway",
  withHourly(function(h) h.precipitation_probability[22] = 45 end).hours[1].chance == 50)
check.that("should show a dash when an hour's chance is missing",
  check.contains(cardOf(withHourly(function(h) h.precipitation_probability[22] = nil end)), "20°—NOW"))
check.that("should show a dash when an hour's temperature is missing",
  check.contains(cardOf(withHourly(function(h) h.temperature_2m[21] = nil end)), "—20%NOW"))

local noHourly = response()
noHourly.hourly = nil
check.that("should list no hours when hourly is missing", #weather.reading(noHourly).hours == 0)
local noTime = response()
noTime.current.time = nil
check.that("should list no hours when the current time is missing", #weather.reading(noTime).hours == 0)

local function oneHour(chance)
  local single = weather.reading(response())
  single.hours = { { label = "NOW", chance = chance, temp = 5, icon = "" } }
  return weather.html(single, "Ankara")
end
check.that("should dim a chance under 30%", check.contains(oneHour(20), 'class="chance dim"'))
check.that("should not dim a chance of 30% or more", not check.contains(oneHour(30), 'class="chance dim"'))

check.that("should show each hour's chance on the card", check.contains(page, "20%NOW"))
local _, columns = weather.html(reading, "Ankara"):gsub("class=hour>", "")
check.that("should render a column per hour", columns == 12)
check.that("should title the row with what the % means", check.contains(page, "PRECIP %"))
check.that("should omit the hourly row when there are no hours",
  not check.contains(cardOf(weather.reading(noHourly)), "PRECIP %"))
check.that("should make the card taller when there are hours",
  weather.height(reading) > weather.height(weather.reading(noHourly)))

check.that("should show today's sunrise", check.contains(page, "07:12"))
check.that("should show today's sunset", check.contains(page, "16:48"))
check.that("should omit sunrise and sunset when the daily answer lacks them",
  not check.contains(cardOf(withHourly(function(_, data) data.daily.sunrise, data.daily.sunset = nil, nil end)), "󰖜"))

check.that("should show the time of the reading next to the place", check.contains(page, "ANKARA · 20:30"))
check.that("should omit the time when the current time is missing",
  not check.contains(cardOf(weather.reading(noTime)), "ANKARA ·"))

local url = weather.url(39.93, 32.85)
check.that("should ask for the given latitude", check.contains(url, "latitude=39.93"))
check.that("should ask for the given longitude", check.contains(url, "longitude=32.85"))
check.that("should ask for the local time zone", check.contains(url, "timezone=auto"))
check.that("should ask for the chance of rain each hour", check.contains(url, "hourly=precipitation_probability"))
check.that("should ask for each hour's temperature, sky and daylight",
  check.contains(url, "temperature_2m,weather_code,is_day&daily"))
check.that("should ask for sunrise and sunset", check.contains(url, "sunrise,sunset"))
check.that("should ask for four days", check.contains(url, "forecast_days=4"))

check.finish()
