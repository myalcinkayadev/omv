-- Behavior of the lyrics window: reading LRC, finding the line at a position, asking LRCLIB,
-- caching what it answered, and the page. Run through lyrics_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local lyrics = require("lyrics")
local theme = require("theme")

local one = lyrics.parse("[01:23.45] line")
check.that("should read a stamp's time in seconds", one and math.abs(one[1].time - 83.45) < 1e-9)
check.that("should read the text after a stamp", one and one[1].text == "line")

local chorus = lyrics.parse("[00:10.00][00:50.00] chorus")
check.that("should give a line for every stamp on one line", chorus and #chorus == 2)
check.that("should give each stamp its own time", chorus and chorus[2].time == 50)

local shuffled = lyrics.parse("[00:20.00] second\n[00:05.00] first")
check.that("should sort lines by time when the LRC is out of order", shuffled and shuffled[1].text == "first")

local tagged = lyrics.parse("[ar:Korn]\n[length:03:20]\n[00:01.00] go")
check.that("should skip metadata tags", tagged and #tagged == 1)

local gap = lyrics.parse("[00:01.00] go\n[00:04.00]\n[00:08.00] back")
check.that("should keep an empty stamped line as a blank gap", gap and gap[2].text == "")

check.that("should read a stamp without hundredths", lyrics.parse("[00:07] seven")[1].time == 7)
check.that("should read a stamp with thousandths", math.abs(lyrics.parse("[00:07.250] x")[1].time - 7.25) < 1e-9)
check.that("should give no lines for empty input", lyrics.parse("") == nil)
check.that("should give no lines for nil input", lyrics.parse(nil) == nil)
check.that("should give no lines for text without stamps", lyrics.parse("just words") == nil)

local song = lyrics.parse("[00:05.00] a\n[00:10.00] b\n[00:15.00] c")
check.that("should pick no line before the first stamp", lyrics.lineAt(song, 2) == 0)
check.that("should pick the line whose stamp equals the position", lyrics.lineAt(song, 10) == 2)
check.that("should pick the line a position falls inside", lyrics.lineAt(song, 12.5) == 2)
check.that("should pick the last line once past the end", lyrics.lineAt(song, 999) == 3)

check.that("should move the position on by the time passed while playing",
  lyrics.position({ position = 30, readAt = 100, playing = true }, 102.5) == 32.5)
check.that("should hold the position while paused",
  lyrics.position({ position = 30, readAt = 100, playing = false }, 160) == 30)

local url = lyrics.url({ artist = "Simon & Garfunkel", title = "The Boxer", album = "Bridge", duration = 308.6 })
check.that("should ask LRCLIB's get endpoint", check.contains(url, "https://lrclib.net/api/get?"))
check.that("should escape & in the artist", check.contains(url, "artist_name=Simon%20%26%20Garfunkel"))
check.that("should escape spaces in the title", check.contains(url, "track_name=The%20Boxer"))
check.that("should round the duration to whole seconds", check.contains(url, "duration=309"))
check.that("should escape non-ASCII letters as UTF-8 bytes",
  check.contains(lyrics.url({ artist = "Sezen Aksu", title = "Gülümse", album = "", duration = 200 }), "G%C3%BCl%C3%BCmse"))

local both = lyrics.choose(200, { syncedLyrics = "[00:01.00] synced", plainLyrics = "plain" })
check.that("should prefer synced lyrics when both exist", both.synced and both.lines[1].text == "synced")
local plain = lyrics.choose(200, { syncedLyrics = nil, plainLyrics = "one\ntwo" })
check.that("should fall back to plain lyrics when there are no synced ones", plain.synced == false and plain.lines[2].text == "two")
check.that("should say there are no lyrics when LRCLIB doesn't know the song", lyrics.choose(404, nil).message == "No lyrics for this song")
check.that("should say a song is instrumental", lyrics.choose(200, { instrumental = true }).message == "Instrumental")
check.that("should say there are no lyrics when the answer has neither kind",
  lyrics.choose(200, { syncedLyrics = "", plainLyrics = "" }).message == "No lyrics for this song")
check.that("should give nothing for a failed request, so it is tried again", lyrics.choose(500, nil) == nil)

local synced = lyrics.cacheText(200, { syncedLyrics = "[00:01.00] hey", plainLyrics = "hey" })
check.that("should read back cached synced lyrics", lyrics.readCache(synced).lines[1].text == "hey")
check.that("should read back cached lyrics as synced", lyrics.readCache(synced).synced == true)
check.that("should read back cached plain lyrics", lyrics.readCache(lyrics.cacheText(200, { plainLyrics = "a\nb" })).lines[2].text == "b")
check.that("should read back a cached song without lyrics", lyrics.readCache(lyrics.cacheText(404, nil)).message == "No lyrics for this song")
check.that("should cache nothing for a failed request", lyrics.cacheText(500, nil) == nil)
check.that("should give nothing for an empty cache file", lyrics.readCache("") == nil)
check.that("should give nothing for a corrupt cache file", lyrics.readCache("garbage\n[00:01.00] x") == nil)

local track = { artist = "Tool", title = "Schism" }
local page = lyrics.html(track, { synced = true, lines = lyrics.parse("[00:01.00] <b>&") })
check.that("should escape HTML in lyric text", check.contains(page, "&lt;b&gt;&amp;"))
check.that("should show the title", check.contains(check.visible(page), "Schism"))
check.that("should show the artist", check.contains(check.visible(page), "Tool"))
check.that("should show a message instead of lines", check.contains(check.visible(lyrics.html(track, { message = "Instrumental" })), "Instrumental"))
check.that("should show a wait message while nothing is known", check.contains(check.visible(lyrics.html(nil, nil)), "Nothing playing"))

local timed = lyrics.parse("[00:05.00] a\n[00:10.00] b\n[00:15.00] c")
local leadIn = lyrics.timing(timed, 0, 2, 200)
check.that("should time the lead-in from 0 to the first line when no line has started",
  leadIn.elapsed == 2 and leadIn.length == 5)
local middle = lyrics.timing(timed, 2, 12, 200)
check.that("should time a line until the next line's stamp", middle.elapsed == 2 and middle.length == 5)
local last = lyrics.timing(timed, 3, 20, 200)
check.that("should time the last line until the track ends", last.elapsed == 5 and last.length == 185)
check.that("should give no length when the last line starts after the track's end",
  lyrics.timing(timed, 3, 20, 10) == nil)

local staged = lyrics.html(track, { synced = true, lines = lyrics.parse("[00:04.00] first\n[00:08.00]\n[00:12.00] back") })
local _, leadAt = staged:find('class="line break lead"', 1, true)
check.that("should start synced lyrics with a lead-in line before the first words",
  leadAt ~= nil and leadAt < staged:find(">first<", 1, true))
local _, breaks = staged:gsub('class="line break', "")
check.that("should mark an empty stamped line as a break", breaks == 2)
check.that("should show a pause mark when the player is paused",
  check.contains(lyrics.html(track, { synced = true, lines = timed }, true), '<body class="paused"'))

local cover = "https://example.com/cover.jpg"
local covered = lyrics.html(track, { synced = true, lines = timed }, false, cover)
check.that("should show the album cover when there is artwork", check.contains(covered, '<img class="cover" src="' .. cover .. '"'))
check.that("should paint the background from the album cover", check.contains(covered, 'class="glow" style="--art: url(&quot;' .. cover .. '&quot;)"'))
check.that("should fall back to a plain background when there is no artwork",
  not check.contains(lyrics.html(track, { synced = true, lines = timed }), 'class="glow"'))
check.that("should escape a quote in the artwork address",
  check.contains(lyrics.html(track, { message = "Instrumental" }, false, 'x" onerror="y'), 'x&quot; onerror=&quot;y'))
local beside = lyrics.html({ artist = "Arch Enemy", title = "Blood in the Water" }, { message = "Instrumental" }, false, cover)
local _, coverAt = beside:find('class="cover"', 1, true)
check.that("should show the title and artist next to the cover",
  coverAt ~= nil and beside:find("Blood in the Water", coverAt, true) ~= nil and beside:find("Arch Enemy", coverAt, true) ~= nil)

local search = lyrics.artworkSearchUrl({ artist = "Arch Enemy", album = "Will To Power" })
check.that("should build an iTunes Search URL for the artist and album",
  search == "https://itunes.apple.com/search?term=Arch%20Enemy%20Will%20To%20Power&entity=album&limit=1")
check.that("should pick the largest artwork size from an iTunes answer",
  lyrics.artworkFromSearch({ resultCount = 1, results = { { artworkUrl100 = "https://is1.mzstatic.com/a/100x100bb.jpg" } } })
    == "https://is1.mzstatic.com/a/1200x1200bb.jpg")
check.that("should give no artwork when iTunes finds nothing", lyrics.artworkFromSearch({ resultCount = 0, results = {} }) == nil)

local function luminance(hex)
  local function channel(at)
    local c = tonumber(hex:sub(at, at + 1), 16) / 255
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * channel(2) + 0.7152 * channel(4) + 0.0722 * channel(6)
end
local function contrast(a, b)
  local high, low = math.max(luminance(a), luminance(b)), math.min(luminance(a), luminance(b))
  return (high + 0.05) / (low + 0.05)
end
local tokyoNight = theme.tokens({ background = "#1a1b26", foreground = "#a9b1d6", accent = "#7aa2f7", muted = "#414868" })
local latte = theme.tokens({ background = "#eff1f5", foreground = "#4c4f69", accent = "#1e66f5", muted = "#acb0be" })

local vivid = lyrics.accent({ { r = 0.5, g = 0.5, b = 0.5 }, { r = 0.9, g = 0.2, b = 0.1 }, { r = 0.4, g = 0.35, b = 0.3 } })
check.that("should pick the most vibrant color as the accent", vivid:sub(2, 3) > vivid:sub(4, 5) and vivid:sub(2, 3) > vivid:sub(6, 7))
local deep = lyrics.accent({ { r = 0.15, g = 0.0, b = 0.35 } })
check.that("should lighten a dark accent until it reads on black", contrast(deep, "#000000") >= 4.5)
check.that("should lighten a dark accent until it reads on a dark theme's background",
  contrast(lyrics.accent({ { r = 0.15, g = 0.0, b = 0.35 } }, tokyoNight), tokyoNight.bg) >= 4.5)
check.that("should darken a pale accent until it reads on a light theme's background",
  contrast(lyrics.accent({ { r = 0.95, g = 0.6, b = 0.6 } }, latte), latte.bg) >= 4.5)
check.that("should give no accent for a grayscale cover",
  lyrics.accent({ { r = 0.1, g = 0.1, b = 0.1 }, { r = 0.8, g = 0.78, b = 0.8 } }) == nil)
check.that("should give no accent when there are no samples", lyrics.accent({}) == nil)

check.that("should give the page the accent color",
  check.contains(lyrics.html(track, { message = "Instrumental" }, false, nil, "#ff3b30"), "--accent: #ff3b30"))
local covered = lyrics.html(track, { synced = true, lines = timed }, false, cover)
check.that("should use the theme's accent when the cover gives none",
  check.contains(theme.recolor(covered, latte), "--accent: #1e66f5"))
check.that("should draw no black on a light theme", not check.contains(theme.recolor(covered, latte), "#000"))
check.that("should draw no black shadow on a light theme", not check.contains(theme.recolor(covered, latte), "rgba(0, 0, 0"))
-- What a rule in the page's style sets, as written.
local function rule(html, selector, property)
  return html:match(selector:gsub("%p", "%%%0") .. " {[^}]*" .. property .. ": ([^;}]+)")
end
local function blend(top, bottom, alpha)
  return theme.mix(bottom, top, alpha)
end
local staged2 = lyrics.html(track, { synced = true, lines = timed }, false, cover)
local nextOpacity = tonumber(rule(staged2, ".line.next", "opacity"))
check.that("should keep the next line readable on black",
  nextOpacity ~= nil and contrast(blend("#ffffff", "#000000", nextOpacity), "#000000") >= 4.5)
check.that("should keep the next line dimmer than the current one", nextOpacity ~= nil and nextOpacity < 1)
for _, part in ipairs({ ".artist", ".times" }) do
  check.that("should keep " .. part .. " readable on Vantablack",
    contrast(rule(staged2, part, "color") or "#000000", "#000000") >= 4.5)
  check.that("should keep " .. part .. " readable on a dark theme",
    contrast(rule(theme.recolor(staged2, tokyoNight), part, "color") or tokyoNight.bg, tokyoNight.bg) >= 4.5)
  check.that("should keep " .. part .. " readable on a light theme",
    contrast(rule(theme.recolor(staged2, latte), part, "color") or latte.bg, latte.bg) >= 4.5)
end

check.that("should use the cover's accent over the theme's",
  check.contains(theme.recolor(lyrics.html(track, { message = "Instrumental" }, false, nil, "#ff3b30"), latte), "--accent: #ff3b30"))

-- Fallback search: a cleaned title, and only an answer by the same artist, with the same
-- title and nearly the same length.
check.that("should drop a featured artist from a title", lyrics.cleanTitle("Song (feat. X)") == "Song")
check.that("should drop a remaster suffix from a title", lyrics.cleanTitle("Song - Remastered 2011") == "Song")
check.that("should drop a remaster year suffix from a title", lyrics.cleanTitle("Song - 2011 Remaster") == "Song")
check.that("should drop a live marker from a title", lyrics.cleanTitle("Song (Live)") == "Song")
check.that("should drop a radio edit suffix from a title", lyrics.cleanTitle("Song - Radio Edit") == "Song")
check.that("should keep a title with nothing to drop", lyrics.cleanTitle("Carry the Cross") == "Carry the Cross")
check.that("should keep a title that is only brackets", lyrics.cleanTitle("(Live)") == "(Live)")
check.that("should search LRCLIB with the cleaned title and the artist",
  lyrics.searchUrl({ artist = "Arch Enemy", title = "Song (feat. X)" })
    == "https://lrclib.net/api/search?track_name=Song&artist_name=Arch%20Enemy")

local wanted = { artist = "Arch Enemy", title = "Nemesis - Remastered 2011", duration = 250 }
local function record(fields)
  local found = { artistName = "Arch Enemy", trackName = "Nemesis", duration = 250, plainLyrics = "words" }
  for key, value in pairs(fields) do found[key] = value end
  return found
end
local syncedOne = record({ syncedLyrics = "[00:01.00] x", duration = 251 })
check.that("should pick a synced answer over a plain one",
  lyrics.pickResult({ record({ duration = 250 }), syncedOne }, wanted) == syncedOne)
local closer = record({ duration = 250.5 })
check.that("should pick the answer closest in length",
  lyrics.pickResult({ record({ duration = 251.8 }), closer }, wanted) == closer)
check.that("should skip answers more than 2 s off in length",
  lyrics.pickResult({ record({ duration = 252.5 }), record({ duration = 247 }) }, wanted) == nil)
check.that("should skip an answer by another artist", lyrics.pickResult({ record({ artistName = "Cover Band" }) }, wanted) == nil)
check.that("should match the artist whatever the case and accents",
  lyrics.pickResult({ record({ artistName = "ARCH ENEMY" }) }, wanted) ~= nil
    and lyrics.pickResult({ record({ artistName = "Sézen Aksu" }) }, { artist = "Sezen Aksu", title = "Nemesis", duration = 250 }) ~= nil)
check.that("should skip an answer with another title", lyrics.pickResult({ record({ trackName = "Nemesis Two" }) }, wanted) == nil)
check.that("should give nothing for an empty answer", lyrics.pickResult({}, wanted) == nil)
check.that("should give nothing for an answer that isn't a list", lyrics.pickResult({ message = "error" }, wanted) == nil)
local searchedCache = lyrics.cacheText(200, syncedOne, true)
check.that("should read back lyrics found by search as found by search", lyrics.readCache(searchedCache).searched == true)
check.that("should read back lyrics from the exact lookup as not searched", not lyrics.readCache(synced).searched)
check.that("should mark lyrics found by search on the page",
  check.contains(check.visible(lyrics.html(track, lyrics.readCache(searchedCache))), "found by search"))
check.that("should not mark lyrics from the exact lookup",
  not check.contains(check.visible(lyrics.html(track, lyrics.readCache(synced))), "found by search"))

-- Plain lyrics scroll with the song, still through the intro and outro.
check.that("should hold the top during the intro", lyrics.plainScroll(0.03 * 200, 200) == 0)
check.that("should reach the bottom by the outro", lyrics.plainScroll(0.96 * 200, 200) == 1)
check.that("should scroll in step with the song in between", math.abs(lyrics.plainScroll(100, 200) - 0.5) < 1e-9)
check.that("should give no scroll for an unknown length", lyrics.plainScroll(10, 0) == nil)
check.that("should stay at the bottom past the end", lyrics.plainScroll(240, 200) == 1)

check.finish()
