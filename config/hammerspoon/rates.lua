-- Currency rates for the palette's calculator, from Frankfurter (api.frankfurter.dev): free,
-- no key, rates from central banks and other sources, each quote with its own date. Fetched
-- only when a currency conversion is typed, and again once the saved ones are 4 hours old.
-- Kept as { base, fetched, quotes = { USD = { rate, date } } } in ~/.local/state/omv/rates.json.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local rates = {}

rates.URL = "https://api.frankfurter.dev/v2/rates?base=EUR"
rates.MAX_AGE = 4 * 3600

function rates.path(home)
  return home .. "/.local/state/omv/rates.json"
end

-- Frankfurter's answer, a list of { date, base, quote, rate }, as saved rates; nil when it
-- holds none.
function rates.read(answer, now)
  if type(answer) ~= "table" or #answer == 0 then return nil end
  local quotes, base, count = {}, nil, 0
  for _, entry in ipairs(answer) do
    if type(entry) == "table" and type(entry.quote) == "string" and type(entry.rate) == "number" then
      quotes[entry.quote] = { rate = entry.rate, date = entry.date }
      base = base or entry.base
      count = count + 1
    end
  end
  if count == 0 then return nil end
  return { base = base, fetched = now, quotes = quotes }
end

function rates.stale(saved, now)
  return not saved or now - (saved.fetched or 0) >= rates.MAX_AGE
end

-- The rates to keep after a fetch: the new ones, or the saved ones when it failed.
function rates.after(saved, answer, now)
  return rates.read(answer, now) or saved
end

return rates
