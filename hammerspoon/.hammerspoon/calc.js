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
  return String(Number(value.toPrecision(10)));
}

if (typeof module !== "undefined") module.exports = omvCalc;
