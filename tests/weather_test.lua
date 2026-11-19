-- Behavior of the weather bar item and card. Run through weather_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local weather = require("weather")

-- Two days of hours from midnight on 2026-11-08. Each hour's chance is its hour of the day,
-- its temperature that plus 0.4, its sky clear, and it is day from 07:00 to 16:00.
-- Index 21 is 20:00 and index 22 is 21:00 on the first day.
local function hourly()
  local times, chances, temperatures, codes, days, amounts, uvs = {}, {}, {}, {}, {}, {}, {}
  for index = 0, 47 do
    local hour = index % 24
    times[#times + 1] = string.format("2026-11-%02dT%02d:00", 8 + math.floor(index / 24), hour)
    chances[#chances + 1] = hour
    temperatures[#temperatures + 1] = hour + 0.4
    codes[#codes + 1] = 0
    days[#days + 1] = (hour >= 7 and hour < 17) and 1 or 0
    amounts[#amounts + 1] = 0
    uvs[#uvs + 1] = 0
  end
  return { time = times, precipitation_probability = chances, temperature_2m = temperatures, weather_code = codes,
    is_day = days, precipitation = amounts, uv_index = uvs }
end

-- Shaped like Open-Meteo's answer to weather.url, after JSON decoding.
local function response()
  return {
    current = {
      temperature_2m = 4.6, apparent_temperature = 0.8, relative_humidity_2m = 43,
      wind_speed_10m = 19.7, wind_direction_10m = 200, uv_index = 3.4, weather_code = 0, is_day = 0, time = "2026-11-08T20:30",
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
check.that("should show feels-like on the card", check.contains(page, "Feels 1°"))
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
check.that("should take an hour's temperature from its start", reading.hours[1].temp == 20)
check.that("should take an hour's icon from the value at its end",
  withHourly(function(h) h.weather_code[22] = 61 end).hours[1].icon == weather.icon(61, false))
check.that("should take an hour's rain from the value at its end",
  withHourly(function(h) h.precipitation[21] = 0; h.precipitation[22] = 1.2 end).hours[1].rain == 1.2)

local noHourly = response()
noHourly.hourly = nil
check.that("should list no hours when hourly is missing", #weather.reading(noHourly).hours == 0)
local noTime = response()
noTime.current.time = nil
check.that("should list no hours when the current time is missing", #weather.reading(noTime).hours == 0)

-- Rain by strength, from millimetres an hour.
check.that("should call a trace of rain no rain", weather.strength(0.1) == nil)
check.that("should call under 2.5 mm an hour light", weather.strength(0.6) == "light")
check.that("should call 2.5 mm an hour moderate", weather.strength(2.5) == "moderate")
check.that("should call 7.6 mm an hour heavy", weather.strength(7.6) == "heavy")

-- Index 24 is 23:00, the end of the hour from 22:00; index 25 is 00:00, the end of 23:00's.
local rainy = withHourly(function(h) h.precipitation[24] = 1; h.precipitation[25] = 3 end)
check.that("should sum up coming rain by its start, end and heaviest hour",
  weather.summary(rainy) == "Rain from 22:00 to 00:00, heaviest at 23:00.")
check.that("should start the summary at now when it rains now",
  check.contains(weather.summary(withHourly(function(h) h.precipitation[22] = 1 end)), "Rain from now"))
check.that("should sum up a dry spell by where the temperature goes",
  weather.summary(reading) == "Dry. Cooling to 0° by 00:00.")
check.that("should name when fog sets in on a dry spell",
  weather.summary(withHourly(function(h) for i = 26, 34 do h.weather_code[i] = 45 end end))
    == "Dry. Cooling to 0° by 00:00, fog from 00:00.")
check.that("should show the summary on the card", check.contains(page, "Dry. Cooling to 0° by 00:00."))

local rainyPage = weather.html(withHourly(function(h)
  h.precipitation[24], h.precipitation[25], h.precipitation[26] = 1, 3, 1
end), "Ankara")
check.that("should name only the strongest run of rain on the card",
  check.contains(rainyPage, ">moderate<") and not check.contains(rainyPage, ">light<"))
check.that("should name no rain on a dry card", not check.contains(weather.html(reading, "Ankara"), "class=rain"))

-- The hours as one line, with the sky only where it changes.
local html = weather.html(reading, "Ankara")
check.that("should draw the hours as one temperature line", check.contains(html, "<path class=line"))
local _, skies = html:gsub("class=sky ", "")
check.that("should show the sky only where it changes", skies == 2)
local _, bands = html:gsub("class=band ", "")
check.that("should shade a band for every hour's sky", bands == 12)
local _, temps = html:gsub("class=lbl ", "")
check.that("should label every hour's temperature", temps == 12)
local _, clocks = html:gsub("class=tm ", "")
check.that("should label every hour's time", clocks == 12)
check.that("should not title the hours", not check.contains(page, "NEXT 12 HOURS") and not check.contains(page, "PRECIP"))
check.that("should draw a flat line when every hour is the same",
  not check.contains(weather.html(withHourly(function(h) for i = 1, #h.temperature_2m do h.temperature_2m[i] = 5 end end), "Ankara"), "nan"))
check.that("should omit the hours when there are none",
  not check.contains(weather.html(weather.reading(noHourly), "Ankara"), "<path class=line"))
check.that("should make the card taller when there are hours",
  weather.height(reading) > weather.height(weather.reading(noHourly)))
check.that("should make the card taller when rain needs its row",
  weather.height(withHourly(function(h) h.precipitation[24] = 3 end)) > weather.height(reading))

-- Night, from sunset to sunrise, shaded on the hours.
check.that("should shade the night that falls in the hours", check.contains(html, "class=night"))
local afternoon = withHourly(function(_, data) data.current.time = "2026-11-08T12:30" end)
check.that("should mark sunset where it falls in the hours", check.contains(weather.html(afternoon, "Ankara"), "class=sunset"))
check.that("should mark no sunset when it has passed", not check.contains(html, "class=sunset"))
check.that("should show today's sunrise and sunset at the arc's ends", check.contains(page, "07:1216:48"))
check.that("should count down to tomorrow's sunrise after sunset", check.contains(page, "Sunrise in 10h 43m"))
check.that("should count down to sunset during the day", check.contains(cardOf(afternoon), "Sunset in 4h 18m"))
check.that("should omit the arc when the daily answer lacks sunrise and sunset",
  not check.contains(weather.html(withHourly(function(_, data) data.daily.sunrise, data.daily.sunset = nil, nil end), "Ankara"), "class=arc"))

-- The header: the sky in words, today's high and low, and UV.
check.that("should name the sky in words", weather.sky(2) == "Partly cloudy" and weather.sky(45) == "Fog" and weather.sky(95) == "Thunderstorm")
check.that("should name an unknown sky cloudy", weather.sky(12345) == "Cloudy")
check.that("should show the sky in words on the card", check.contains(page, "Clear"))
check.that("should show today's high and low", check.contains(page, "H 7° L -2°"))
check.that("should round UV", reading.uv == 3)
check.that("should rate UV on the WHO scale", weather.uvLevel(2) == "low" and weather.uvLevel(3) == "moderate"
  and weather.uvLevel(6) == "high" and weather.uvLevel(8) == "very high" and weather.uvLevel(11) == "extreme")
check.that("should show UV with its rating", check.contains(page, "3 moderate"))
check.that("should take an hour's UV from its start", withHourly(function(h) h.uv_index[21] = 4.6 end).hours[1].uv == 5)

-- Wind with an arrow toward where it blows.
check.that("should read where the wind comes from", reading.windFrom == 200)
check.that("should point the wind arrow where it blows", check.contains(html, "rotate(20deg)"))
check.that("should draw no arrow when the wind's direction is missing",
  not check.contains(weather.html(withHourly(function(_, data) data.current.wind_direction_10m = nil end), "Ankara"), "class=arrow"))

-- Days on one scale: the coldest low at the left end, the warmest high at the right.
check.that("should start the coldest day's bar at the left", check.contains(html, "left:0%"))
check.that("should end the warmest day's bar at the right", check.contains(html, "right:0%"))

check.that("should put the place on its own line above the temperature",
  html:find("class=place", 1, true) < html:find("class=temp", 1, true))
check.that("should show the time of the reading next to the place", check.contains(page, "ANKARA · 20:30"))
check.that("should omit the time when the current time is missing",
  not check.contains(cardOf(weather.reading(noTime)), "ANKARA ·"))

local url = weather.url(39.93, 32.85)
check.that("should ask for the given latitude", check.contains(url, "latitude=39.93"))
check.that("should ask for the given longitude", check.contains(url, "longitude=32.85"))
check.that("should ask for the local time zone", check.contains(url, "timezone=auto"))
check.that("should ask for each hour's rain, temperature, sky and daylight",
  check.contains(url, "hourly=precipitation,temperature_2m,weather_code,is_day,uv_index&daily"))
check.that("should ask where the wind comes from", check.contains(url, "wind_direction_10m"))
check.that("should ask for UV now and each hour", check.contains(url, "uv_index,weather_code,is_day&hourly")
  and check.contains(url, "is_day,uv_index&daily"))
check.that("should ask for sunrise and sunset", check.contains(url, "sunrise,sunset"))
check.that("should ask for four days", check.contains(url, "forecast_days=4"))

check.finish()
