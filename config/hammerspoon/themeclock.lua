-- Theme by the clock: ~/.config/omv/theme-clock names a day theme and a night theme, and the
-- theme switches at sunrise and sunset where the Mac is. The sun's times are worked out on
-- the Mac from the location, with the sunrise equation, so nothing is fetched. Without a
-- location, or where the sun doesn't rise or set that day, day runs from 7:00 to 19:00.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local themeclock = {}

themeclock.PATH = (os.getenv("HOME") or "") .. "/.config/omv/theme-clock"
themeclock.DAY_STARTS = 7
themeclock.NIGHT_STARTS = 19

local function plainName(name)
  return type(name) == "string" and name:match("^[%w%-]+$") ~= nil
end

-- The file's "day = <theme>" and "night = <theme>" lines, as { day, night }, or nil unless
-- both name a theme. Lines starting with # are comments.
function themeclock.parse(text)
  local found = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local key, value = line:match("^%s*(%a+)%s*=%s*([%w%-]+)%s*$")
    if (key == "day" or key == "night") and plainName(value) then found[key] = value end
  end
  if not (found.day and found.night) then return nil end
  return found
end

local rad, deg = math.pi / 180, 180 / math.pi

-- Days from 1970-01-01 to the date, in the proleptic Gregorian calendar.
local function daysFromCivil(year, month, day)
  year = month <= 2 and year - 1 or year
  local era = math.floor(year / 400)
  local yearOfEra = year - era * 400
  local dayOfYear = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
  local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
  return era * 146097 + dayOfEra - 719468
end

local function dayOfYear(year, month, day)
  return daysFromCivil(year, month, day) - daysFromCivil(year, 1, 1) + 1
end

-- Hours after midnight UTC of the sun rising or setting, or nil when it doesn't that day.
-- The sunrise equation as the Almanac for Computers (1990) gives it, to about a minute.
local function utcHours(rising, date, latitude, longitude)
  local zenith = 90.833
  local longitudeHours = longitude / 15
  local t = dayOfYear(date.year, date.month, date.day) + ((rising and 6 or 18) - longitudeHours) / 24
  local anomaly = 0.9856 * t - 3.289
  local trueLongitude = (anomaly + 1.916 * math.sin(anomaly * rad) + 0.020 * math.sin(2 * anomaly * rad) + 282.634) % 360
  local ascension = (deg * math.atan(0.91764 * math.tan(trueLongitude * rad))) % 360
  ascension = (ascension + math.floor(trueLongitude / 90) * 90 - math.floor(ascension / 90) * 90) / 15
  local sinDeclination = 0.39782 * math.sin(trueLongitude * rad)
  local cosDeclination = math.cos(math.asin(sinDeclination))
  local cosHour = (math.cos(zenith * rad) - sinDeclination * math.sin(latitude * rad)) / (cosDeclination * math.cos(latitude * rad))
  if cosHour > 1 or cosHour < -1 then return nil end
  local hour = (rising and (360 - deg * math.acos(cosHour)) or (deg * math.acos(cosHour))) / 15
  local localMean = hour + ascension - 0.06571 * t - 6.622
  return (localMean - longitudeHours) % 24
end

-- The epoch second within 12 hours of the place's solar noon on the date.
local function nearNoon(date, longitude, hours)
  local midnight = daysFromCivil(date.year, date.month, date.day) * 86400
  local noon = midnight + 12 * 3600 - longitude / 15 * 3600
  local time = midnight + hours * 3600
  while time - noon > 12 * 3600 do time = time - 86400 end
  while noon - time > 12 * 3600 do time = time + 86400 end
  return math.floor(time + 0.5)
end

-- Sunrise and sunset on the date ({ year, month, day }) at the place, as epoch seconds, or
-- nil when the sun doesn't rise or doesn't set that day.
function themeclock.sun(date, latitude, longitude)
  local rise, set = utcHours(true, date, latitude, longitude), utcHours(false, date, latitude, longitude)
  if not (rise and set) then return nil end
  return nearNoon(date, longitude, rise), nearNoon(date, longitude, set)
end

-- "day" or "night" at now. sunrise and sunset are today's, or nil; then local is the local
-- time as os.date("*t") gives it, and day runs from 7:00 to 19:00.
function themeclock.period(now, sunrise, sunset, localTime)
  if sunrise and sunset then return (now >= sunrise and now < sunset) and "day" or "night" end
  local hour = localTime and localTime.hour or 12
  return (hour >= themeclock.DAY_STARTS and hour < themeclock.NIGHT_STARTS) and "day" or "night"
end

return themeclock
