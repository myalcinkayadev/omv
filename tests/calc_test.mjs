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

process.exit(failed ? 1 : 0);
