// Behavior of the calendar card's world clocks, clocks.js. Run through clocks_test.sh with node.

import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { clock, difference, show } = require(process.env.OMV_CLOCKS);
let failed = 0;
const check = (name, passed) => {
  console.log((passed ? "ok   - " : "FAIL - ") + name);
  if (!passed) failed += 1;
};

// 27 November 2026, 12:00 UTC, seen from Istanbul (UTC+3, no daylight saving).
const NOON_UTC = Date.UTC(2026, 10, 27, 12, 0, 30);
const ISTANBUL = 180;

check("should show the time there when the zone is known", clock("America/New_York", NOON_UTC, ISTANBUL).time === "07:00");
check("should show a whole-hour difference when the zone is behind", clock("America/New_York", NOON_UTC, ISTANBUL).difference === "−8 h");
check("should show a whole-hour difference when the zone is ahead", clock("Asia/Tokyo", NOON_UTC, ISTANBUL).difference === "+6 h");
check("should show a half-hour difference when the zone is offset by 30 minutes", clock("Asia/Kolkata", NOON_UTC, ISTANBUL).difference === "+2:30");
check("should show a quarter-hour difference when the zone is offset by 45 minutes", clock("Asia/Kathmandu", NOON_UTC, ISTANBUL).difference === "+2:45");
check("should show a half-hour difference when the zone is behind by a part hour", clock("America/St_Johns", NOON_UTC, ISTANBUL).difference === "−6:30");
check("should show 0 h when the zone keeps local time", clock("Europe/Istanbul", NOON_UTC, ISTANBUL).difference === "0 h");
check("should show no weekday when the date there is today's", clock("America/New_York", NOON_UTC, ISTANBUL).day === "");

const LATE = Date.UTC(2026, 10, 27, 20, 30);
check("should show the weekday when the date there is tomorrow", clock("Pacific/Auckland", LATE, ISTANBUL).day === "Sat");
check("should show the time after midnight when the date there is tomorrow", clock("Pacific/Auckland", LATE, ISTANBUL).time === "09:30");
const EARLY = Date.UTC(2026, 10, 26, 22, 30);
check("should show the weekday when the date there is yesterday", clock("America/Los_Angeles", EARLY, ISTANBUL).day === "Thu");
check("should show midnight as 00 when the zone is at midnight", clock("UTC", Date.UTC(2026, 10, 27, 0, 5), ISTANBUL).time === "00:05");

check("should follow daylight saving when the zone is in summer time", clock("America/New_York", Date.UTC(2026, 6, 1, 12), ISTANBUL).difference === "−7 h");

check("should give null when the zone is unknown", clock("Mars/Olympus_Mons", NOON_UTC, ISTANBUL) === null);
check("should give null when the zone is empty", clock("", NOON_UTC, ISTANBUL) === null);

check("should show a minus sign when the difference is negative", difference(-90) === "−1:30");
check("should show a plus sign when the difference is positive", difference(330) === "+5:30");

// The page's rows, with only what clocks.js reads and writes.
const row = (zone) => {
  const time = { textContent: "" }, diff = { textContent: "" };
  return { dataset: { zone }, time, diff, querySelector: (selector) => (selector === ".time" ? time : diff) };
};
const unknown = row("Nowhere/Atlantis"), known = row("UTC");
globalThis.document = { querySelectorAll: () => [unknown, known] };
show();
check("should mark an unknown time zone instead of a time", unknown.time.textContent === "unknown time zone");
check("should show no difference when the zone is unknown", unknown.diff.textContent === "");
check("should fill in a time when the zone is known", /^(\w{3} )?\d\d:\d\d$/.test(known.time.textContent));

process.exit(failed === 0 ? 0 : 1);
