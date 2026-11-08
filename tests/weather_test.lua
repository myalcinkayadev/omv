-- Behavior of the weather bar item and card. Run through weather_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local weather = require("weather")

-- Shaped like Open-Meteo's answer to weather.url, after JSON decoding.
local function response()
  return {
    current = {
      temperature_2m = 4.6, apparent_temperature = 0.8, relative_humidity_2m = 43,
      wind_speed_10m = 19.7, weather_code = 0, is_day = 0,
    },
    daily = {
      time = { "2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11" },
      weather_code = { 3, 2, 73, 45 },
      temperature_2m_max = { 7, 8.2, 4.6, 11.4 },
      temperature_2m_min = { -2, -3.4, -1, 0.3 },
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

local url = weather.url(39.93, 32.85)
check.that("should ask for the given latitude", check.contains(url, "latitude=39.93"))
check.that("should ask for the given longitude", check.contains(url, "longitude=32.85"))
check.that("should ask for the local time zone", check.contains(url, "timezone=auto"))
check.that("should ask for four days", check.contains(url, "forecast_days=4"))

check.finish()
