// The calendar card's world clocks: each .clock row's data-zone, shown as its time, its
// weekday when the date there isn't today's, and its difference from local time. Worked out
// in the page with Intl, so no command runs. calendar.lua inlines this file into the card.

const OMV_MINUTE = 60 * 1000;
const OMV_DAY = 24 * 60 * OMV_MINUTE;
const OMV_WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const omvPad = (number) => String(number).padStart(2, "0");

// zone's wall clock at now, as milliseconds read as UTC; null for a zone Intl doesn't know.
function omvWallClock(zone, now) {
  let format;
  try {
    format = new Intl.DateTimeFormat("en-US", { timeZone: zone, hourCycle: "h23",
      year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric" });
  } catch (error) {
    return null;
  }
  const parts = {};
  for (const part of format.formatToParts(now)) parts[part.type] = Number(part.value);
  return Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute);
}

// minutes ahead of local time as "+5:30", "−7 h" or "0 h", with a real minus sign.
function omvDifference(minutes) {
  if (minutes === 0) return "0 h";
  const sign = minutes < 0 ? "−" : "+";
  const hours = Math.floor(Math.abs(minutes) / 60);
  const rest = Math.abs(minutes) % 60;
  return rest === 0 ? `${sign}${hours} h` : `${sign}${hours}:${omvPad(rest)}`;
}

// { time, day, difference } for zone at now, or null for an unknown zone. localOffset is
// local time's minutes ahead of UTC, passed in so the tests don't depend on the Mac's zone.
function omvClock(zone, now, localOffset) {
  const wall = omvWallClock(zone, now);
  if (wall === null) return null;
  const local = Math.floor((now + localOffset * OMV_MINUTE) / OMV_MINUTE) * OMV_MINUTE;
  const date = new Date(wall);
  const otherDay = Math.floor(wall / OMV_DAY) !== Math.floor(local / OMV_DAY);
  return {
    time: `${omvPad(date.getUTCHours())}:${omvPad(date.getUTCMinutes())}`,
    day: otherDay ? OMV_WEEKDAYS[date.getUTCDay()] : "",
    difference: omvDifference(Math.round((wall - local) / OMV_MINUTE)),
  };
}

function omvShowClocks() {
  const now = Date.now();
  const localOffset = -new Date(now).getTimezoneOffset();
  for (const row of document.querySelectorAll(".clock")) {
    const clock = omvClock(row.dataset.zone, now, localOffset);
    row.querySelector(".time").textContent = clock ? `${clock.day} ${clock.time}`.trim() : "unknown time zone";
    row.querySelector(".diff").textContent = clock ? clock.difference : "";
  }
}

// Redrawn on each new minute while the card has focus. The card is hidden, not unloaded,
// when it closes, so the first tick without focus stops, and focus starts it again.
let omvClockTimer = null;
function omvTickClocks() {
  clearTimeout(omvClockTimer);
  omvClockTimer = null;
  if (document.hidden || !document.hasFocus()) return;
  omvShowClocks();
  omvClockTimer = setTimeout(omvTickClocks, OMV_MINUTE - (Date.now() % OMV_MINUTE));
}

if (typeof document !== "undefined" && document.querySelector(".clock")) {
  omvShowClocks();
  omvClockTimer = setTimeout(omvTickClocks, OMV_MINUTE - (Date.now() % OMV_MINUTE));
  window.addEventListener("focus", () => { if (omvClockTimer === null) omvTickClocks(); });
}

if (typeof module !== "undefined") module.exports = { clock: omvClock, difference: omvDifference, show: omvShowClocks };
