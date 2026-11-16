-- Weather (the bar item, Option+Shift+O). It follows the Mac's location, which macOS asks
-- to share with Hammerspoon the first time. Read every 30 minutes, on wake and when the
-- card opens. The last good reading stays shown when a later one fails.

local shell = require("shell")
local weather = require("weather")

local feature = {}

local WEATHER_REFRESH_SECONDS = 1800
local LOCATION_RETRY_SECONDS = 5
local LOCATION_RETRIES = 6
local weatherReading, weatherCity, weatherProblem = nil, nil, nil
local weatherBarShown = nil

local function drawWeatherBar()
  local properties = { "drawing=off" }
  if weatherReading then
    properties = { "drawing=on", "icon=" .. weatherReading.icon, "label=" .. weather.barLabel(weatherReading) }
  end
  local key = table.concat(properties, "\n")
  if key == weatherBarShown then return end
  weatherBarShown = key
  local arguments = { "--set", "weather" }
  for _, property in ipairs(properties) do arguments[#arguments + 1] = property end
  arguments[#arguments + 1] = "--trigger"
  arguments[#arguments + 1] = "bar_fit"
  hs.task.new(shell.SKETCHYBAR, nil, arguments):start()
end

local function showWeather()
  shell.show("weather", shell.anchored(weather.WIDTH, weather.height(weatherReading), "weather"),
    weather.html(weatherReading, weatherCity, weatherProblem), function() shell.close() end)
end

local function weatherChanged()
  drawWeatherBar()
  if shell.isOpen("weather") then showWeather() end
end

local function fetchWeather(location)
  -- Two decimals is about a kilometre: close enough for weather, and no more exact than needed.
  local url = weather.url(string.format("%.2f", location.latitude), string.format("%.2f", location.longitude))
  hs.http.asyncGet(url, nil, function(status, body)
    local ok, data = pcall(hs.json.decode, body or "")
    local reading = status == 200 and ok and weather.reading(data) or nil
    if reading then
      weatherReading, weatherProblem = reading, nil
    else
      weatherProblem = status == 200 and "Couldn't read the weather" or "No connection"
    end
    weatherChanged()
  end)
  hs.location.geocoder.lookupLocation(location, function(found, places)
    if not found or not places or not places[1] then return end
    weatherCity = places[1].locality or places[1].name
    weatherChanged()
  end)
end

local function locationProblem()
  if not hs.location.servicesEnabled() then return "Turn on Location Services in System Settings" end
  local status = hs.location.authorizationStatus()
  if status == "denied" or status == "restricted" then return "Allow Location for Hammerspoon in System Settings" end
  return nil
end

local function readWeather(tries)
  tries = tries or 0
  local problem = locationProblem()
  if problem then
    weatherProblem = problem
    return weatherChanged()
  end
  hs.location.start()
  local location = hs.location.get()
  -- One fix is enough, so Location Services isn't kept running between readings.
  if location then
    hs.location.stop()
    return fetchWeather(location)
  end
  -- The first fix, or the permission answer, can take a few seconds.
  if tries < LOCATION_RETRIES then
    hs.timer.doAfter(LOCATION_RETRY_SECONDS, function() readWeather(tries + 1) end)
  else
    hs.location.stop()
    weatherProblem = "Couldn't find your location"
    weatherChanged()
  end
end

function feature.toggle()
  if shell.isOpen("weather") then return shell.close() end
  showWeather()
  readWeather()
end

-- A restarted bar has lost the item, so the reading is sent again even if unchanged.
function feature.redrawBar()
  weatherBarShown = nil
  drawWeatherBar()
end

-- Globals, so the timer and the watcher are never garbage-collected.
omvWeatherTimer = hs.timer.doEvery(WEATHER_REFRESH_SECONDS, function() readWeather() end)
omvWeatherWakeWatcher = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then readWeather() end
end):start()
readWeather()

return feature
