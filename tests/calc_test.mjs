// Behavior of the palette's calculator, calc.js. Run through calc_test.sh with node.

import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const calc = require(process.env.OMV_CALC);
let failed = 0;
const check = (name, passed) => {
  console.log((passed ? "ok   - " : "FAIL - ") + name);
  if (!passed) failed += 1;
};

check("should multiply when typed 2*35", calc("2*35") === "70");
check("should multiply before adding", calc("2+3*4") === "14");
check("should work out brackets first", calc("(2+3)*4") === "20");
check("should raise to a power from the right", calc("2^3^2") === "512");
check("should take a remainder with %", calc("10%3") === "1");
check("should read decimals", calc("1.5*2") === "3");
check("should read a leading minus", calc("-3+5") === "2");
check("should ignore spaces", calc(" 2 * 35 ") === "70");
check("should round to 10 significant digits", calc("1/3") === "0.3333333333");
check("should trim trailing zeros", calc("0.1+0.2") === "0.3");
check("should show a large whole number in full", calc("2^40") === "1099511627776");
check("should round a whole number past exact range when it is huge", calc("2^60") === "1.152921505e+18");
check("should give nothing for a lone number", calc("42") === null);
check("should give nothing for a bracketed lone number", calc("(42)") === null);
check("should give nothing for a window name with digits", calc("omv-14") === null);
check("should give nothing for text after a number", calc("2 apples") === null);
check("should give nothing for a trailing operator", calc("2*") === null);
check("should give nothing for an unclosed bracket", calc("(2+3") === null);
check("should give nothing for an empty query", calc("") === null);
check("should give nothing when dividing by zero", calc("1/0") === null);
check("should give nothing when the result overflows", calc("10^400") === null);
check("should give nothing for a function call", calc("alert(1)") === null);
check("should give nothing for a property name", calc("2*constructor") === null);

// Conversions: units, currencies and dates, with the clock and rates passed in.
const convert = calc.convert;
const NOW = new Date(2026, 10, 20, 12, 0).getTime();
const RATES = { base: "EUR", fetched: NOW, quotes: { USD: { rate: 1.08, date: "2026-11-19" }, TRY: { rate: 45.2, date: "2026-11-20" } } };
const value = (text, rates) => { const answer = convert(text, { now: NOW, rates }); return answer && answer.value; };
const note = (text, rates) => { const answer = convert(text, { now: NOW, rates }); return answer && answer.note; };

check("should convert km to miles when typed 5 km to mi", value("5 km to mi") === "3.107 mi");
check("should read in the same as to", value("5 km in mi") === "3.107 mi");
check("should read a unit written against the number", value("5km to mi") === "3.107 mi");
check("should convert fahrenheit to celsius", value("100 f to c") === "37.78 °C");
check("should convert celsius to fahrenheit", value("-40 c to f") === "-40 °F");
check("should treat GB and MB as decimal", value("1.5 GB to MB") === "1500 MB");
check("should treat GiB and MiB as binary", value("1 GiB to MiB") === "1024 MiB");
check("should read units in any letter case", value("5 KM TO MI") === "3.107 mi");
check("should convert mass", value("1 kg to lb") === "2.205 lb");
check("should convert volume", value("1 gal to l") === "3.785 l");
check("should convert time", value("90 min to h") === "1.5 h");
check("should convert speed", value("100 km/h to mph") === "62.14 mph");
check("should read in as inches", value("12 in to cm") === "30.48 cm");
check("should give nothing when the units measure different things", value("5 kg to km") === null);
check("should give nothing for an unknown unit", value("5 parsecs to km") === null);
check("should give nothing for a unit with no amount", value("km to mi") === null);
check("should leave plain arithmetic to the calculator", value("2*35") === null);

check("should convert a currency with the rates given", value("100 usd to eur", RATES) === "92.59 EUR");
check("should convert between two currencies through the base", value("10 usd to try", RATES) === "418.52 TRY");
check("should show the rate's date beside a currency result", note("100 usd to eur", RATES) === "rate of Nov 19");
check("should give nothing for a currency when there are no rates", value("100 usd to eur") === null);
check("should give nothing for an unknown currency code", value("100 xyz to eur", RATES) === null);
check("should want rates for what looks like a currency conversion", convert.wantsRates("100 usd to eur") === true);
check("should not want rates for a unit conversion", convert.wantsRates("5 km to mi") === false);
check("should convert a currency named in words when typed 3 euro to try", value("3 euro to try", RATES) === value("3 eur to try", RATES));
check("should read a plural currency name", value("3 euros to try", RATES) === value("3 eur to try", RATES));
check("should read dollars as USD", value("10 dollars to try", RATES) === "418.52 TRY");
check("should read lira as TRY", value("10 usd to lira", RATES) === "418.52 TRY");
check("should read tl as TRY", value("418.52 tl to usd", RATES) === "10.00 USD");
check("should keep pounds a weight", value("5 pounds to kg") === "2.268 kg");
check("should give nothing for an unknown currency name", value("3 euro to xyz", RATES) === null);
check("should want rates for a currency named in words", convert.wantsRates("3 euro to lira") === true);

check("should give the date a number of days from today", value("today + 30 days") === "Sun Dec 20 2026");
check("should go back from today with a minus", value("today - 1 week") === "Fri Nov 13 2026");
check("should read in 3 weeks as from today", value("in 3 weeks") === "Fri Dec 11 2026");
check("should keep to the month's last day when adding a month", value("2027-01-31 + 1 month") === "Sun Feb 28 2027");
check("should count the days until a date", value("days until 2026-12-25") === "35 days");
check("should count one day as a day", value("days until 2026-11-21") === "1 day");
check("should count the days since a date", value("days since 2026-11-10") === "10 days");
check("should give nothing for an impossible date", value("days until 2026-13-01") === null);
check("should give nothing for today alone", value("today") === null);

process.exit(failed ? 1 : 0);
