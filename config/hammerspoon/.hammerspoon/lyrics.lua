-- The lyrics window: reading LRC, finding the line at the player's position, asking LRCLIB
-- for a track's lyrics, caching what it answered, and the page that shows them.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local lyrics = {}

local NO_LYRICS = "No lyrics for this song"

-- A line of lyrics: when it starts, in seconds, and its words.
-- Returns them sorted by time, or nil when the text holds no stamped line.
function lyrics.parse(text)
  if not text then return nil end
  local lines = {}
  for raw in (text .. "\n"):gmatch("(.-)\r?\n") do
    -- Lua patterns can't repeat a group, so the stamps come off one at a time.
    local words = raw:gsub("^%s+", "")
    repeat
      local stripped = words:gsub("^%[[^%]]*%]", "", 1)
      local changed = stripped ~= words
      words = stripped
    until not changed
    words = words:gsub("^%s+", ""):gsub("%s+$", "")
    for minutes, seconds in raw:gmatch("%[(%d+):(%d+%.?%d*)%]") do
      lines[#lines + 1] = { time = tonumber(minutes) * 60 + tonumber(seconds), text = words }
    end
  end
  if #lines == 0 then return nil end
  -- Lines with the same stamp keep their order in the file.
  for index, line in ipairs(lines) do line.order = index end
  table.sort(lines, function(a, b)
    if a.time ~= b.time then return a.time < b.time end
    return a.order < b.order
  end)
  return lines
end

-- The index of the line playing at seconds, or 0 before the first one starts.
function lyrics.lineAt(lines, seconds)
  local found = 0
  for index, line in ipairs(lines) do
    if line.time > seconds then break end
    found = index
  end
  return found
end

-- The player's position now, from the last time it was read. Asking the player every
-- frame would cost an AppleScript call each time.
function lyrics.position(state, now)
  if not state.playing then return state.position end
  return state.position + (now - state.readAt)
end

-- How far down unsynced lyrics should be, from 0 to 1: still through the first and last
-- twentieth of the song, which are mostly intro and outro, and in step with it between.
-- nil when the song's length is unknown.
function lyrics.plainScroll(position, duration)
  if not duration or duration <= 0 then return nil end
  local share = (position / duration - 0.05) / 0.9
  return math.max(0, math.min(1, share))
end

local function present(text)
  return type(text) == "string" and text:find("%S") ~= nil
end

local function escapeQuery(text)
  return (tostring(text or ""):gsub("[^%w%-%._~]", function(byte)
    return string.format("%%%02X", byte:byte())
  end))
end

-- LRCLIB matches a track on all four, and the duration within a couple of seconds.
function lyrics.url(track)
  return "https://lrclib.net/api/get?artist_name=" .. escapeQuery(track.artist)
    .. "&track_name=" .. escapeQuery(track.title)
    .. "&album_name=" .. escapeQuery(track.album)
    .. "&duration=" .. math.floor((track.duration or 0) + 0.5)
end

-- Words that LRCLIB's search may tack on or leave off: a featured artist, a remaster, a
-- live recording or a radio edit. Matched on a lower-case copy, which has the same bytes.
local TITLE_EXTRAS = {
  "%s*[%(%[]feat%.?%s[^%)%]]*[%)%]]",
  "%s*[%(%[]ft%.?%s[^%)%]]*[%)%]]",
  "%s*[%(%[]featuring%s[^%)%]]*[%)%]]",
  "%s*[%(%[][^%)%]]*remaster[^%)%]]*[%)%]]",
  "%s*[%(%[]live[^%)%]]*[%)%]]",
  "%s*[%(%[]radio edit[^%)%]]*[%)%]]",
  "%s+%-%s+[^%-]*remaster[^%-]*$",
  "%s+%-%s+live[^%-]*$",
  "%s+%-%s+radio edit$",
}

-- A title without those extras; the title itself when nothing would be left.
function lyrics.cleanTitle(title)
  local cleaned = tostring(title or "")
  repeat
    local before = cleaned
    for _, pattern in ipairs(TITLE_EXTRAS) do
      local from, to = cleaned:lower():find(pattern)
      if from then cleaned = cleaned:sub(1, from - 1) .. cleaned:sub(to + 1) end
    end
  until cleaned == before
  cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
  if cleaned == "" then return title end
  return cleaned
end

-- LRCLIB's search, for when the exact lookup finds nothing. Sends only the title and artist.
function lyrics.searchUrl(track)
  return "https://lrclib.net/api/search?track_name=" .. escapeQuery(lyrics.cleanTitle(track.title))
    .. "&artist_name=" .. escapeQuery(track.artist)
end

-- Accented letters folded to plain ones, so "Sézen" and "Sezen" compare equal.
local FOLDED = {
  ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ã"] = "a", ["å"] = "a",
  ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
  ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["ı"] = "i", ["İ"] = "i",
  ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["ö"] = "o", ["õ"] = "o", ["ø"] = "o",
  ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
  ["ç"] = "c", ["ğ"] = "g", ["ş"] = "s", ["ñ"] = "n", ["ß"] = "ss",
  ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ö"] = "o", ["Ú"] = "u", ["Ü"] = "u",
  ["Ç"] = "c", ["Ğ"] = "g", ["Ş"] = "s", ["Ñ"] = "n",
}

-- A name as compared: folded, lower case, without a leading "the" and without punctuation.
local function comparable(name)
  local folded = tostring(name or ""):gsub("[\xC0-\xDF][\x80-\xBF]", FOLDED)
  return (folded:lower():gsub("^%s*the%s+", ""):gsub("[^%w]", ""))
end

local MAX_LENGTH_GAP = 2

local function hasWords(found)
  return type(found.syncedLyrics) == "string" or type(found.plainLyrics) == "string" or found.instrumental
end

local function fits(found, track)
  return type(found) == "table" and hasWords(found)
    and comparable(found.artistName) == comparable(track.artist)
    and comparable(lyrics.cleanTitle(found.trackName)) == comparable(lyrics.cleanTitle(track.title))
    and math.abs((tonumber(found.duration) or -1e9) - (track.duration or 0)) <= MAX_LENGTH_GAP
end

local function better(a, b, track)
  local aSynced, bSynced = present(a.syncedLyrics), present(b.syncedLyrics)
  if aSynced ~= bSynced then return aSynced end
  return math.abs(a.duration - track.duration) < math.abs(b.duration - track.duration)
end

-- The search answer to use: same artist, same title once cleaned, at most 2 seconds off in
-- length; synced over plain, then the closest in length. nil when none fits.
function lyrics.pickResult(results, track)
  if type(results) ~= "table" then return nil end
  local best = nil
  for _, found in ipairs(results) do
    if fits(found, track) and (not best or better(found, best, track)) then best = found end
  end
  return best
end

local function plainLines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    lines[#lines + 1] = { text = line }
  end
  return lines
end

-- What to show for LRCLIB's answer: { synced, lines } or { message }.
-- nil for a failed request, so it is neither shown as final nor cached.
function lyrics.choose(status, data)
  if status == 404 then return { message = NO_LYRICS } end
  if status ~= 200 or type(data) ~= "table" then return nil end
  if data.instrumental then return { message = "Instrumental" } end
  local synced = present(data.syncedLyrics) and lyrics.parse(data.syncedLyrics) or nil
  if synced then return { synced = true, lines = synced } end
  if present(data.plainLyrics) then return { synced = false, lines = plainLines(data.plainLyrics) } end
  return { message = NO_LYRICS }
end

-- A cache file is the kind on its first line, then the lyrics as LRCLIB gave them. Lyrics
-- found by search say so after the kind, so the page can say so too.
function lyrics.cacheText(status, data, searched)
  local chosen = lyrics.choose(status, data)
  if not chosen then return nil end
  if chosen.message then return chosen.message == "Instrumental" and "instrumental\n" or "none\n" end
  local how = searched and " search\n" or "\n"
  if chosen.synced then return "synced" .. how .. data.syncedLyrics end
  return "plain" .. how .. data.plainLyrics
end

local function fromCache(kind, body)
  if kind == "synced" then return lyrics.choose(200, { syncedLyrics = body }) end
  if kind == "plain" then return lyrics.choose(200, { plainLyrics = body }) end
  if kind == "instrumental" then return { message = "Instrumental" } end
  if kind == "none" then return { message = NO_LYRICS } end
  return nil
end

function lyrics.readCache(text)
  local kind, how, body = (text or ""):match("^(%a+) ?(%a*)\n(.*)$")
  local shown = fromCache(kind, body)
  if shown and how == "search" then shown.searched = true end
  return shown
end

-- How far into the line at index the position is, and how long that line lasts: until the
-- next line, or the end of the track for the last one. Index 0 is the lead-in before the
-- first line. nil when the line has no length to show.
function lyrics.timing(lines, index, position, duration)
  local start = index == 0 and 0 or lines[index].time
  local finish = lines[index + 1] and lines[index + 1].time or duration
  if not finish or finish <= start then return nil end
  return { elapsed = position - start, length = finish - start }
end

local function escapeHtml(text)
  return (tostring(text):gsub("[&<>\"]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

-- Apple's search finds the album's cover when the player has none to give.
function lyrics.artworkSearchUrl(track)
  return "https://itunes.apple.com/search?term=" .. escapeQuery(track.artist .. " " .. (track.album or ""))
    .. "&entity=album&limit=1"
end

-- The answer names a 100px cover; the same address serves any size asked for.
function lyrics.artworkFromSearch(data)
  local found = type(data) == "table" and type(data.results) == "table" and data.results[1]
  local small = found and found.artworkUrl100
  if type(small) ~= "string" then return nil end
  return (small:gsub("100x100bb", "1200x1200bb"))
end

local function relativeLuminance(color)
  local function channel(c)
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
end

-- WCAG's 4.5:1 against the background the accent is drawn on.
local function readableOn(background, color)
  local a, b = relativeLuminance(color), relativeLuminance(background)
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05) >= 4.5
end

local function hex(color)
  local function byte(c) return math.floor(math.min(1, math.max(0, c)) * 255 + 0.5) end
  return string.format("#%02x%02x%02x", byte(color.r), byte(color.g), byte(color.b))
end

local function rgb(code)
  return { r = tonumber(code:sub(2, 3), 16) / 255, g = tonumber(code:sub(4, 5), 16) / 255, b = tonumber(code:sub(6, 7), 16) / 255 }
end

local function vibrantest(samples)
  local best, bestVibrancy = nil, 0.2
  for _, color in ipairs(samples) do
    local high = math.max(color.r, color.g, color.b)
    local low = math.min(color.r, color.g, color.b)
    local saturation = high > 0 and (high - low) / high or 0
    local vibrancy = saturation * high
    if saturation >= 0.3 and vibrancy > bestVibrancy then best, bestVibrancy = color, vibrancy end
  end
  return best
end

-- The cover's one accent: its most vibrant sampled color, moved toward the theme's text
-- color until it reads on the theme's background. None for a grayscale cover, which has no
-- color worth taking, so the page keeps the theme's own accent.
-- samples are { r, g, b } from 0 to 1; tokens are theme.tokens' bg and fg, black and white
-- when nil.
function lyrics.accent(samples, tokens)
  local best = vibrantest(samples)
  if not best then return nil end
  local background, text = rgb(tokens and tokens.bg or "#000000"), rgb(tokens and tokens.fg or "#ffffff")
  local color = { r = best.r, g = best.g, b = best.b }
  -- Each step closes a tenth of the gap, so 60 steps all but reach the text color.
  for _ = 1, 60 do
    if readableOn(background, color) then break end
    color = { r = color.r + (text.r - color.r) * 0.1, g = color.g + (text.g - color.g) * 0.1, b = color.b + (text.b - color.b) * 0.1 }
  end
  return hex(color)
end

-- omv's own stage for the lyrics, read at a glance from across the room mid-workout:
-- - The theme's background, with one static glow of the cover behind everything, tinted with the
--   cover's accent. Drawn once and never moved, so it costs nothing while playing.
-- - A bar in the accent fills under the line being sung until the next one starts.
-- - The next line stays readable to sing ahead; the others fade with distance.
-- - Title and artist in omv's monospace; the cover framed like omv's cards.
-- - A narrow tile puts a small cover above the words; a wide window puts it beside them.
-- - In a break, accent dots count down to the next line. Everything stills while paused.
local STYLE = [[
  * { box-sizing: border-box; margin: 0; }
  html, body { height: 100%; background: #000; color: #fff; overflow: hidden;
    font-family: -apple-system, "SF Pro Display", system-ui, sans-serif;
    -webkit-user-select: none; cursor: default; }
  /* The theme's accent until a cover gives its own. */
  body { position: relative; --accent: #8d8d8d; }
  .glow { position: absolute; inset: -25%; background: var(--art) center / cover;
    filter: blur(110px) saturate(1.3); opacity: 0.32; }
  .shade { position: absolute; inset: 0;
    background: radial-gradient(ellipse at 20% 25%, color-mix(in srgb, var(--accent) 16%, transparent), transparent 60%),
      radial-gradient(ellipse at center, transparent 30%, color-mix(in srgb, #000 70%, transparent)); }

  .stage { position: relative; height: 100%; display: flex; flex-direction: column; padding: 4vh 6vw 0; }
  .playing { display: flex; align-items: center; gap: 16px; flex-shrink: 0; padding-bottom: 2.5vh; }
  .cover { width: min(14vh, 22vw); aspect-ratio: 1; object-fit: cover; border: 1px solid #8d8d8d; flex-shrink: 0; }
  .meta { flex: 1; min-width: 0;
    font-family: "JetBrainsMono Nerd Font Propo", "JetBrainsMono Nerd Font Mono", monospace; }
  .title, .artist { white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    text-transform: uppercase; letter-spacing: 2px; }
  .title { font-size: max(15px, 2.6vh); font-weight: 700; }
  /* Labels a step below white, still readable from a distance in every theme. */
  .artist { color: #d4d4d4; font-size: max(13px, 2.2vh); margin-top: 0.5vh; }
  .pause { display: none; color: var(--accent); }
  body.paused .pause { display: inline; }
  .track { height: max(4px, 0.6vh); background: #333; overflow: hidden; margin-top: 1.8vh; }
  .track i { display: block; height: 100%; background: var(--accent); transform-origin: left; transform: scaleX(0); }
  .times { display: flex; justify-content: space-between; color: #d4d4d4; font-size: max(13px, 2.2vh);
    margin-top: 1vh; letter-spacing: 1px; font-variant-numeric: tabular-nums; }
  .times .at { color: #fff; font-weight: 700; }
  .source { color: #d4d4d4; font-size: max(11px, 1.6vh); margin-top: 1vh; letter-spacing: 1px; }

  .lines { flex: 1; min-height: 0; overflow: hidden; transition: opacity 0.4s; }
  /* Room above the first line and below the last, so either can sit where the eye rests. */
  .synced::before { content: ""; display: block; height: 28%; }
  .synced::after { content: ""; display: block; height: 72%; }
  body.paused .lines { opacity: 0.45; }
  .line { font-weight: 800; line-height: 1.1; letter-spacing: -0.015em; text-wrap: balance;
    font-size: min(9vw, 9.5vh); padding: 1.8vh 0; color: #fff; transform-origin: left center;
    opacity: 0; transform: scale(0.9);
    transition: opacity 0.4s, transform 0.4s cubic-bezier(0.2, 0.8, 0.2, 1); }
  .line.now { opacity: 1; transform: none; }
  /* The next line stays readable, to sing ahead; the sung ones fade. */
  .line.next { opacity: 0.62; transform: scale(0.92); }
  .line.past { opacity: 0.32; }
  .line.far { opacity: 0.14; }
  .meter { height: max(6px, 0.9vh); margin-top: 1.6vh; width: min(100%, 8em); background: #333; overflow: hidden; }
  .meter i { display: block; height: 100%; background: var(--accent); transform-origin: left; transform: scaleX(0); }
  .line.break { min-height: 1.1em; }
  .dots { display: none; gap: 0.3em; padding-top: 0.25em; }
  .line.break.now .dots { display: flex; }
  .dots i { width: 0.28em; height: 0.28em; background: #333; transition: background 0.3s; }
  .dots i.lit { background: var(--accent); }
  .plain { overflow-y: auto; scrollbar-width: none; padding-bottom: 4vh; }
  .plain::-webkit-scrollbar { display: none; }
  .plain .line { opacity: 1; transform: none; font-weight: 700; font-size: max(16px, 4vmin); }
  .message { flex: 1; display: flex; align-items: center; color: #7a7a7a;
    font-weight: 800; font-size: min(7vw, 7vh); }

  /* A wide window: the cover large on the left, the words on the right. */
  @media (min-aspect-ratio: 5/4) {
    .stage { flex-direction: row; align-items: stretch; gap: 6vw; padding: 0 5vw; }
    .playing { width: min(30vw, 58vh); flex-direction: column; align-items: stretch; justify-content: center;
      gap: 2.4vh; padding: 0; }
    .cover { width: 100%; }
    .meta { flex: none; }
    .line { font-size: min(5.6vw, 9vh); }
    .message { font-size: min(4.5vw, 7vh); }
  }
  @media (prefers-reduced-motion: reduce) {
    .line, .lines, .dots i { transition: none; }
  }
]]

-- Hammerspoon calls omvAt when the line changes, the player pauses or resumes, or the
-- position is read again. The bars, dots and clock then run on their own.
local SCRIPT = [[
  const box = document.querySelector(".synced");
  const lines = Array.from(document.querySelectorAll(".synced .line"));
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const meter = document.createElement("div");
  meter.className = "meter";
  meter.innerHTML = "<i></i>";
  let timers = [];
  let clock = null;

  const later = (seconds, action) => timers.push(setTimeout(action, Math.max(0, seconds) * 1000));

  // From the fraction already done, filling to the end over the time left, if playing.
  const fill = (bar, done, seconds, playing) => {
    bar.style.transition = "none";
    bar.style.transform = `scaleX(${Math.min(1, Math.max(0, done))})`;
    void bar.offsetWidth;
    if (!playing || seconds <= 0) return;
    bar.style.transition = `transform ${seconds}s linear`;
    bar.style.transform = "scaleX(1)";
  };

  // Each dot lights at its quarter of the break, so the last one means "now".
  const countDown = (line, elapsed, length, playing) => {
    line.querySelectorAll(".dots i").forEach((dot, at) => {
      const due = (length * (at + 1)) / 4 - elapsed;
      dot.classList.toggle("lit", due <= 0);
      if (due > 0 && playing) later(due, () => dot.classList.add("lit"));
    });
  };

  const clockText = (seconds) => {
    const whole = Math.max(0, Math.floor(seconds));
    return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
  };

  const runClock = (trackAt, duration, playing) => {
    const at = document.querySelector(".times .at");
    const left = document.querySelector(".times .left");
    if (!at || !(duration > 0)) return;
    clearInterval(clock);
    const started = performance.now();
    const draw = () => {
      const now = Math.min(duration, trackAt + (playing ? (performance.now() - started) / 1000 : 0));
      at.textContent = clockText(now);
      left.textContent = "-" + clockText(duration - now);
    };
    draw();
    if (playing) clock = setInterval(draw, 1000);
  };

  // Unsynced lyrics follow the song, unless scrolled by hand in the last 10 seconds.
  const plain = document.querySelector(".plain");
  let scrolledByHand = -Infinity;
  if (plain) ["wheel", "touchmove", "keydown"].forEach((name) =>
    plain.addEventListener(name, () => { scrolledByHand = performance.now(); }, { passive: true }));
  window.omvScroll = (share) => {
    if (!plain || performance.now() - scrolledByHand < 10000) return;
    plain.scrollTo({ top: share * (plain.scrollHeight - plain.clientHeight), behavior: still ? "auto" : "smooth" });
  };

  window.omvAt = (index, elapsed, length, playing, trackAt, duration) => {
    timers.forEach(clearTimeout);
    timers = [];
    document.body.classList.toggle("paused", !playing);
    const track = document.querySelector(".track i");
    if (track && duration > 0) fill(track, trackAt / duration, duration - trackAt, playing);
    runClock(trackAt, duration, playing);
    lines.forEach((line, at) => {
      line.classList.toggle("now", at === index);
      line.classList.toggle("next", at === index + 1);
      line.classList.toggle("past", at === index - 1);
      line.classList.toggle("far", at === index - 2 || at === index + 2);
    });
    const now = lines[index];
    meter.remove();
    if (!now || !(length > 0)) return;
    // The box alone scrolls: scrollIntoView would scroll the page too. The playing line
    // rests near the top third, where the eye lands, with what comes next below it.
    box.scrollTo({ top: now.offsetTop - box.offsetTop - box.clientHeight * 0.28,
      behavior: still ? "auto" : "smooth" });
    if (now.classList.contains("break")) return countDown(now, elapsed, length, playing);
    now.appendChild(meter);
    fill(meter.firstChild, elapsed / length, length - elapsed, playing);
  };
]]

local DOTS = '<span class="dots"><i></i><i></i><i></i><i></i></span>'

local function syncedRows(lines)
  local rows = { '<div class="line break lead">' .. DOTS .. "</div>" }
  for _, line in ipairs(lines) do
    if line.text == "" then
      rows[#rows + 1] = '<div class="line break">' .. DOTS .. "</div>"
    else
      rows[#rows + 1] = '<div class="line">' .. escapeHtml(line.text) .. "</div>"
    end
  end
  return '<div class="lines synced">' .. table.concat(rows) .. "</div>"
end

local function plainRows(lines)
  local rows = {}
  for _, line in ipairs(lines) do
    rows[#rows + 1] = '<div class="line">' .. escapeHtml(line.text) .. "</div>"
  end
  return '<div class="lines plain">' .. table.concat(rows) .. "</div>"
end

local function words(track, shown)
  if not track then return '<div class="message">Nothing playing</div>' end
  if not shown then return '<div class="message">Finding lyrics…</div>' end
  if shown.message then return '<div class="message">' .. escapeHtml(shown.message) .. "</div>" end
  if shown.synced then return syncedRows(shown.lines) end
  return plainRows(shown.lines)
end

-- The cover, title, artist and the whole track's progress.
local function nowPlaying(track, shown, artwork)
  if not track then return "" end
  local cover = artwork and ('<img class="cover" src="' .. escapeHtml(artwork) .. '" alt="">') or ""
  local source = (shown and shown.searched) and '<div class="source">found by search</div>' or ""
  return '<div class="playing">' .. cover .. '<div class="meta">'
    .. '<div class="title"><span class="pause">❚❚ </span>' .. escapeHtml(track.title) .. "</div>"
    .. '<div class="artist">' .. escapeHtml(track.artist) .. "</div>"
    .. '<div class="track"><i></i></div><div class="times"><span class="at"></span><span class="left"></span></div>'
    .. source
    .. "</div></div>"
end

local function background(artwork)
  if not artwork then return "" end
  return '<div class="glow" style="--art: url(&quot;' .. escapeHtml(artwork) .. '&quot;)"></div><div class="shade"></div>'
end

-- track is nil while nothing plays; shown is nil while its lyrics are on their way.
-- artwork is the cover's address, a data: URL or https, or nil when there is none.
-- accent is the cover's color, from lyrics.accent; the theme's accent without one.
function lyrics.html(track, shown, paused, artwork, accent)
  local accentStyle = accent and (' style="--accent: ' .. escapeHtml(accent) .. '"') or ""
  return "<!doctype html><html><head><meta charset=\"utf-8\"><title>Lyrics</title><style>" .. STYLE
    .. "</style></head><body" .. (paused and ' class="paused"' or "") .. accentStyle .. ">"
    .. background(artwork) .. '<main class="stage">' .. nowPlaying(track, shown, artwork) .. words(track, shown) .. "</main>"
    .. "<script>" .. SCRIPT .. "</script></body></html>"
end

return lyrics
