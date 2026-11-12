-- Lyrics (a right-click on the bar's track): the playing song's lyrics in a window of its
-- own, the line being sung large in the middle. The window is a small helper app rather
-- than a Hammerspoon webview, which can't hide its title bar buttons; see lyrics-window.swift.
-- AeroSpace tiles it beside whatever else is on the workspace, and it stays open when focus
-- moves away.
-- Lyrics come from LRCLIB, which is sent the track's artist, title, album and length; when
-- that finds nothing, its search is sent the artist and title. Either way they are cached so
-- a song is asked about only once. The cover comes from the player, else
-- from Apple's iTunes Search, which is sent the artist and album, and is cached the same way.

local lyrics = require("lyrics")
local shell = require("shell")

local feature = {}

local TICK_SECONDS = 0.25
-- The position is counted on locally between reads; a read puts it right after a seek.
local RESYNC_SECONDS = 5
-- Unsynced lyrics are scrolled at most this often; the page eases in between.
local SCROLL_SECONDS = 1
local LYRICS_WINDOW = hs.configdir .. "/lyrics-window.sh"
local CACHE_DIR = shell.STATE_DIR .. "/lyrics"
local PLAYERS = {
  { name = "Music", bundle = "com.apple.Music", durationScale = 1 },
  -- Spotify gives a track's duration in milliseconds.
  { name = "Spotify", bundle = "com.spotify.client", durationScale = 1 / 1000 },
}

-- The helper's task while its window is open.
local window = nil
local timers = {}
local playback = nil
local shown = nil
-- The cover's address for the page: a data: URL or https, nil when there is none.
local artwork = nil
-- The cover's colors, sampled once, so its accent can be worked out again for a new theme.
local samples = nil
local shownIndex = nil
-- When unsynced lyrics were last scrolled, nil until the page has been scrolled once.
local scrolledAt = nil
-- Set after a read of the player, so the page gets the corrected position and play state.
local stale = true

local function trackKey(track)
  return track and (track.artist .. "\n" .. track.title) or nil
end

-- A list, so numbers arrive as numbers whatever the Mac's decimal separator.
-- No variable holds the track: Music reserves words like "playing" and "song".
local function readPlayer(player)
  local ok, answer = hs.osascript.applescript('tell application "' .. player.name .. '"\n'
    .. "if player state is stopped then return {}\n"
    .. "return {player state as string, player position, artist of current track, name of current track, "
    .. "album of current track, duration of current track}\n"
    .. "end tell")
  if not ok or type(answer) ~= "table" or #answer < 6 then return nil end
  return {
    playing = answer[1] == "playing",
    position = tonumber(answer[2]) or 0,
    readAt = hs.timer.secondsSinceEpoch(),
    player = player.name,
    track = { artist = answer[3], title = answer[4], album = answer[5], duration = (tonumber(answer[6]) or 0) * player.durationScale },
  }
end

-- The playing player, else one paused on a track. Never asks one that isn't running,
-- since asking would launch it.
local function readPlayback()
  local paused = nil
  for _, player in ipairs(PLAYERS) do
    if hs.application.applicationsForBundleID(player.bundle)[1] then
      local state = readPlayer(player)
      if state and state.playing then return state end
      paused = paused or state
    end
  end
  return paused
end

local function cachePath(track)
  return CACHE_DIR .. "/" .. hs.hash.SHA1(trackKey(track)) .. ".txt"
end

local function saveCache(track, text)
  hs.fs.mkdir(shell.STATE_DIR)
  hs.fs.mkdir(CACHE_DIR)
  local file = io.open(cachePath(track), "w")
  if not file then return end
  file:write(text)
  file:close()
end

-- One JSON object per line, which hs.json writes with its newlines escaped.
local function send(command)
  window:setInput(hs.json.encode(command) .. "\n")
end

local function render()
  if not window then return end
  shownIndex, scrolledAt = nil, nil
  local tokens = shell.themeTokens()
  local accent = samples and lyrics.accent(samples, tokens)
  -- The window's own color shows before a page draws, and picks a light or dark title bar.
  send({ background = tokens.bg })
  send({ html = shell.themed(lyrics.html(playback and playback.track, shown, playback and not playback.playing, artwork, accent)) })
end

local UNREACHABLE = { message = "Couldn't reach LRCLIB" }

local function stillPlaying(track)
  return trackKey(playback and playback.track) == trackKey(track)
end

local function decoded(body)
  local ok, data = pcall(hs.json.decode, body or "")
  return ok and data or nil
end

-- Shows what the search found, or that there are no lyrics; a failed search is tried again
-- the next time the song plays.
local function searchLyrics(track)
  hs.http.asyncGet(lyrics.searchUrl(track), { ["User-Agent"] = "omv-lyrics" }, function(status, body)
    if not stillPlaying(track) then return end
    if status ~= 200 then
      shown = UNREACHABLE
      return render()
    end
    local found = lyrics.pickResult(decoded(body), track)
    local text = found and lyrics.cacheText(200, found, true) or lyrics.cacheText(404, nil)
    saveCache(track, text)
    shown = lyrics.readCache(text)
    render()
  end)
end

local function fetchLyrics(track)
  hs.http.asyncGet(lyrics.url(track), { ["User-Agent"] = "omv-lyrics" }, function(status, body)
    -- The song may have changed while LRCLIB answered.
    if not stillPlaying(track) then return end
    if status == 404 then return searchLyrics(track) end
    local data = decoded(body)
    local text = lyrics.cacheText(status, data)
    if text then saveCache(track, text) end
    shown = lyrics.choose(status, data) or UNREACHABLE
    render()
  end)
end

local function loadLyrics(track)
  shown = lyrics.readCache(shell.readText(cachePath(track)))
  render()
  if not shown then fetchLyrics(track) end
end

local function artworkPath(track)
  return CACHE_DIR .. "/" .. hs.hash.SHA1(trackKey(track) .. "\n" .. (track.album or "")) .. ".art"
end

-- Small enough to send in each page, large enough for a wide window's cover.
local function imageAddress(image)
  return image:copy():setSize({ w = 800, h = 800 }, true):encodeAsURLString(false, "JPEG")
end

-- A 6 by 6 grid over a shrunken cover is enough to find its most vibrant color.
local function sampleColors(image)
  local small = image:copy():setSize({ w = 18, h = 18 }, true)
  local found = {}
  for x = 1, 16, 3 do
    for y = 1, 16, 3 do
      local color = small:colorAt({ x = x, y = y })
      if color then found[#found + 1] = { r = color.red or 0, g = color.green or 0, b = color.blue or 0 } end
    end
  end
  return found
end

local function showArtwork(track, path)
  if trackKey(playback and playback.track) ~= trackKey(track) then return end
  local image = hs.image.imageFromPath(path)
  if not image then return end
  artwork, samples = imageAddress(image), sampleColors(image)
  render()
end

-- Music hands over the cover's bytes, written straight to the cache.
local function musicArtwork(path)
  local ok, answer = hs.osascript.applescript('tell application "Music"\n'
    .. "if (count of artworks of current track) is 0 then return \"\"\n"
    .. "set art to raw data of artwork 1 of current track\n"
    .. "end tell\n"
    .. 'set target to open for access (POSIX file "' .. path .. '") with write permission\n'
    .. "set eof of target to 0\n"
    .. "write art to target\n"
    .. "close access target\n"
    .. 'return "ok"')
  return ok and answer == "ok"
end

local function spotifyArtworkUrl()
  local ok, answer = hs.osascript.applescript('tell application "Spotify" to return artwork url of current track')
  if not ok or type(answer) ~= "string" or not answer:find("^https://") then return nil end
  return answer
end

-- Kept as a file like Music's, so the page needs no network and its color can be read.
local function downloadArtwork(track, url, path)
  hs.http.asyncGet(url, nil, function(status, body)
    if status ~= 200 or not body or body == "" then return end
    local file = io.open(path, "wb")
    if not file then return end
    file:write(body)
    file:close()
    showArtwork(track, path)
  end)
end

local function searchArtwork(track, path)
  hs.http.asyncGet(lyrics.artworkSearchUrl(track), nil, function(status, body)
    if status ~= 200 then return end
    local ok, data = pcall(hs.json.decode, body or "")
    local url = ok and lyrics.artworkFromSearch(data) or nil
    if url then downloadArtwork(track, url, path) end
  end)
end

local function loadArtwork(track, player)
  artwork, samples = nil, nil
  local path = artworkPath(track)
  hs.fs.mkdir(shell.STATE_DIR)
  -- Music writes the cover here itself, so the folder must already exist.
  hs.fs.mkdir(CACHE_DIR)
  if hs.fs.attributes(path) then return showArtwork(track, path) end
  if player == "Music" and musicArtwork(path) then return showArtwork(track, path) end
  local url = player == "Spotify" and spotifyArtworkUrl() or nil
  if url then return downloadArtwork(track, url, path) end
  searchArtwork(track, path)
end

local function sync()
  local previous = trackKey(playback and playback.track)
  playback = readPlayback()
  stale = true
  local current = trackKey(playback and playback.track)
  if current == previous then return end
  shown = nil
  if not playback then
    artwork, samples = nil, nil
    return render()
  end
  loadArtwork(playback.track, playback.player)
  loadLyrics(playback.track)
end

local function scrollPlain(now)
  if scrolledAt and now - scrolledAt < SCROLL_SECONDS and not stale then return end
  local share = lyrics.plainScroll(lyrics.position(playback, now), playback.track.duration)
  if not share then return end
  scrolledAt, stale = now, false
  send({ js = string.format("omvScroll(%.4f)", share) })
end

local function tick()
  if not playback or not shown or not shown.lines then return end
  local now = hs.timer.secondsSinceEpoch()
  if not shown.synced then return scrollPlain(now) end
  local position = lyrics.position(playback, now)
  local index = lyrics.lineAt(shown.lines, position)
  if index == shownIndex and not stale then return end
  shownIndex, stale = index, false
  local duration = playback.track.duration
  local timing = lyrics.timing(shown.lines, index, position, duration) or { elapsed = 0, length = 0 }
  send({ js = string.format("omvAt(%d, %.3f, %.3f, %s, %.3f, %.3f)", index, timing.elapsed, timing.length,
    tostring(playback.playing), position, duration or 0) })
end

local function stopTimers()
  for _, timer in ipairs(timers) do timer:stop() end
  timers = {}
end

-- The helper says "loaded" for each new page, which knows no line yet, so the next tick
-- sends it one.
local function heard(_, output)
  if output:find("loaded", 1, true) then shownIndex, scrolledAt = nil, nil end
  return true
end

-- Closed from the bar, or by the window itself.
local function closed()
  stopTimers()
  window = nil
end

function feature.toggle()
  if window then return window:terminate() end
  window = hs.task.new(LYRICS_WINDOW, closed, heard)
  if not window:start() then
    window = nil
    return shell.alert("Couldn't open the lyrics window", 2)
  end
  playback, shown = nil, nil
  sync()
  render()
  timers = { hs.timer.doEvery(TICK_SECONDS, tick), hs.timer.doEvery(RESYNC_SECONDS, sync) }
end

shell.onThemeChange(render)

-- Music and Spotify announce a new track, a pause or a seek; init.lua passes it on.
function feature.playerChanged()
  if window then sync() end
end

return feature
