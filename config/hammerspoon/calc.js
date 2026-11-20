// The palette's calculator: omvCalc("2*35") is "70". Reads + - * / % ^, brackets, decimals
// and a leading minus; % is the remainder and ^ binds from the right. Text that isn't a
// whole sum, a lone number, or a result that isn't finite gives null. A parser, never eval,
// so typed text can't run as code. card.lua inlines this file into the palette's page.

function omvCalc(text) {
  const tokens = String(text).match(/\d+(?:\.\d+)?|\.\d+|[-+*\/%^()]|\S/g);
  if (!tokens) return null;
  let at = 0;
  let operators = 0;
  const peek = () => tokens[at];
  const take = () => tokens[at++];

  function expression() {
    let value = term();
    while (peek() === "+" || peek() === "-") {
      operators++;
      value = take() === "+" ? value + term() : value - term();
    }
    return value;
  }

  function term() {
    let value = unary();
    while (peek() === "*" || peek() === "/" || peek() === "%") {
      operators++;
      const operator = take();
      const right = unary();
      value = operator === "*" ? value * right : operator === "/" ? value / right : value % right;
    }
    return value;
  }

  function unary() {
    if (peek() === "-") { take(); return -unary(); }
    return power();
  }

  function power() {
    const base = atom();
    if (peek() !== "^") return base;
    operators++;
    take();
    return Math.pow(base, unary());
  }

  function atom() {
    const token = take();
    if (token === "(") {
      const value = expression();
      if (take() !== ")") throw new Error("unclosed bracket");
      return value;
    }
    if (token === undefined || !/^(\d|\.\d)/.test(token)) throw new Error("not a number");
    return parseFloat(token);
  }

  let value;
  try {
    value = expression();
  } catch (error) {
    return null;
  }
  if (at !== tokens.length || operators === 0 || !Number.isFinite(value)) return null;
  if (Number.isSafeInteger(value)) return String(value);
  // Past 2^53 the digits are no longer exact, so a huge result shows rounded, as 1.15e+18.
  if (Math.abs(value) > Number.MAX_SAFE_INTEGER) return value.toPrecision(10).replace(/\.?0+e/, "e");
  return String(Number(value.toPrecision(10)));
}

// Conversions, for the palette when omvCalc finds no sum: "5 km to mi", "100 usd in eur",
// "today + 30 days", "in 3 weeks", "days until 2026-12-25". context is { now, rates }: now in
// ms, rates as rates.lua keeps them, { base, fetched, quotes = { USD = { rate, date } } }, or
// nothing yet. Gives { value, note } or null; note is the rate's date for a currency.
const OMV_UNITS = (() => {
  const units = {};
  const add = (kind, factor, label, names) => names.forEach((name) => { units[name] = { kind, factor, label }; });
  add("length", 0.001, "mm", ["mm"]); add("length", 0.01, "cm", ["cm"]); add("length", 1, "m", ["m", "meter", "meters"]);
  add("length", 1000, "km", ["km"]); add("length", 0.0254, "in", ["in", "inch", "inches", "\""]);
  add("length", 0.3048, "ft", ["ft", "foot", "feet"]); add("length", 0.9144, "yd", ["yd", "yard", "yards"]);
  add("length", 1609.344, "mi", ["mi", "mile", "miles"]); add("length", 1852, "nmi", ["nmi"]);
  add("mass", 1e-6, "mg", ["mg"]); add("mass", 0.001, "g", ["g", "gram", "grams"]); add("mass", 1, "kg", ["kg"]);
  add("mass", 1000, "t", ["t", "tonne", "tonnes"]); add("mass", 0.028349523125, "oz", ["oz"]);
  add("mass", 0.45359237, "lb", ["lb", "lbs", "pound", "pounds"]); add("mass", 6.35029318, "st", ["st", "stone"]);
  add("volume", 0.001, "ml", ["ml"]); add("volume", 0.01, "cl", ["cl"]); add("volume", 1, "l", ["l", "liter", "liters", "litre", "litres"]);
  add("volume", 0.0295735295625, "fl oz", ["floz"]); add("volume", 0.2365882365, "cup", ["cup", "cups"]);
  add("volume", 0.473176473, "pt", ["pt", "pint", "pints"]); add("volume", 3.785411784, "gal", ["gal", "gallon", "gallons"]);
  add("data", 1, "B", ["b", "byte", "bytes"]); add("data", 1e3, "KB", ["kb"]); add("data", 1e6, "MB", ["mb"]);
  add("data", 1e9, "GB", ["gb"]); add("data", 1e12, "TB", ["tb"]); add("data", 1024, "KiB", ["kib"]);
  add("data", 1024 ** 2, "MiB", ["mib"]); add("data", 1024 ** 3, "GiB", ["gib"]); add("data", 1024 ** 4, "TiB", ["tib"]);
  add("time", 0.001, "ms", ["ms"]); add("time", 1, "s", ["s", "sec", "secs", "second", "seconds"]);
  add("time", 60, "min", ["min", "mins", "minute", "minutes"]); add("time", 3600, "h", ["h", "hr", "hrs", "hour", "hours"]);
  add("time", 86400, "days", ["day", "days"]); add("time", 604800, "weeks", ["week", "weeks"]);
  add("speed", 1, "m/s", ["m/s"]); add("speed", 1 / 3.6, "km/h", ["km/h", "kmh", "kph"]);
  add("speed", 0.44704, "mph", ["mph"]); add("speed", 0.514444, "kn", ["kn", "knot", "knots"]);
  add("temperature", "c", "°C", ["c", "°c", "celsius"]); add("temperature", "f", "°F", ["f", "°f", "fahrenheit"]);
  add("temperature", "k", "K", ["k", "kelvin"]);
  return units;
})();

const OMV_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const OMV_DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const OMV_CONVERSION = /^\s*(-?\d+(?:\.\d+)?|-?\.\d+)\s*([a-z°\/"]+)\s+(?:to|in)\s+([a-z°\/"]+)\s*$/i;

// 4 significant digits, as 3.107 or 37.78; whole thousands and more as they are, to 2 places.
function omvAmount(value) {
  if (Math.abs(value) >= 1000) return String(Math.round(value * 100) / 100);
  return String(Number(value.toPrecision(4)));
}

function omvTemperature(value, from, to) {
  const celsius = from === "c" ? value : from === "f" ? (value - 32) * 5 / 9 : value - 273.15;
  return to === "c" ? celsius : to === "f" ? celsius * 9 / 5 + 32 : celsius + 273.15;
}

function omvUnits(amount, from, to) {
  const source = OMV_UNITS[from], target = OMV_UNITS[to];
  if (!source || !target || source.kind !== target.kind) return null;
  const value = source.kind === "temperature" ? omvTemperature(amount, source.factor, target.factor) : amount * source.factor / target.factor;
  return { value: omvAmount(value) + " " + target.label, note: null };
}

// A rate against the base: 1 for the base itself, nil when the rates don't list the code.
function omvRate(rates, code) {
  if (code === rates.base) return { rate: 1, date: null };
  return rates.quotes[code] || null;
}

function omvShortDate(iso) {
  const [year, month, day] = iso.split("-").map(Number);
  return OMV_MONTHS[month - 1] + " " + day;
}

function omvCurrency(amount, from, to, rates) {
  if (!rates || !rates.quotes) return null;
  const source = omvRate(rates, from.toUpperCase()), target = omvRate(rates, to.toUpperCase());
  if (!source || !target) return null;
  const value = amount / source.rate * target.rate;
  const dates = [source.date, target.date].filter(Boolean).sort();
  return { value: (Math.round(value * 100) / 100).toFixed(2) + " " + to.toUpperCase(), note: dates.length ? "rate of " + omvShortDate(dates[0]) : null };
}

// A real calendar date from YYYY-MM-DD, or null for one such as 2026-13-01.
function omvDate(text) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) return null;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const date = new Date(year, month - 1, day);
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day ? date : null;
}

function omvToday(now) {
  const date = new Date(now);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

// A month or year later keeps to the last day of a shorter month: Jan 31 + 1 month is Feb 28.
function omvShift(date, count, unit) {
  const singular = unit.replace(/s$/, "");
  if (singular === "day" || singular === "week") {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + count * (singular === "week" ? 7 : 1));
  }
  const months = count * (singular === "year" ? 12 : 1);
  const first = new Date(date.getFullYear(), date.getMonth() + months, 1);
  const last = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
  return new Date(first.getFullYear(), first.getMonth(), Math.min(date.getDate(), last));
}

function omvDayName(date) {
  return OMV_DAYS[date.getDay()] + " " + OMV_MONTHS[date.getMonth()] + " " + date.getDate() + " " + date.getFullYear();
}

function omvDates(text, now) {
  const span = "(\\d+)\\s*(days?|weeks?|months?|years?)";
  const shifted = new RegExp("^\\s*(today|\\d{4}-\\d{2}-\\d{2})\\s*([+-])\\s*" + span + "\\s*$", "i").exec(text);
  if (shifted) {
    const start = shifted[1].toLowerCase() === "today" ? omvToday(now) : omvDate(shifted[1]);
    if (!start) return null;
    return { value: omvDayName(omvShift(start, Number(shifted[3]) * (shifted[2] === "-" ? -1 : 1), shifted[4].toLowerCase())), note: null };
  }
  const ahead = new RegExp("^\\s*in\\s+" + span + "\\s*$", "i").exec(text);
  if (ahead) return { value: omvDayName(omvShift(omvToday(now), Number(ahead[1]), ahead[2].toLowerCase())), note: null };
  const counted = /^\s*days\s+(until|since)\s+(\d{4}-\d{2}-\d{2})\s*$/i.exec(text);
  if (!counted) return null;
  const date = omvDate(counted[2]);
  if (!date) return null;
  const days = Math.round((date - omvToday(now)) / 86400000) * (counted[1].toLowerCase() === "since" ? -1 : 1);
  return { value: days + (Math.abs(days) === 1 ? " day" : " days"), note: null };
}

function omvConvert(text, context) {
  const now = (context && context.now) || Date.now();
  const match = OMV_CONVERSION.exec(String(text));
  if (!match) return omvDates(String(text), now);
  const amount = parseFloat(match[1]), from = match[2].toLowerCase(), to = match[3].toLowerCase();
  if (OMV_UNITS[from] || OMV_UNITS[to]) return omvUnits(amount, from, to);
  return omvCurrency(amount, from, to, context && context.rates);
}

// Whether text reads as a currency conversion, three letters to three letters, so the page
// asks Hammerspoon for rates only then.
omvConvert.wantsRates = (text) => {
  const match = OMV_CONVERSION.exec(String(text));
  if (!match) return false;
  const from = match[2].toLowerCase(), to = match[3].toLowerCase();
  return /^[a-z]{3}$/.test(from) && /^[a-z]{3}$/.test(to) && !OMV_UNITS[from] && !OMV_UNITS[to];
};

if (typeof module !== "undefined") {
  module.exports = omvCalc;
  module.exports.convert = omvConvert;
}
