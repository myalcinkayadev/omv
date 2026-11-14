# Palette Calculator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Typing an expression such as `2*35` in Option+Space shows a top row `= 70`; Enter copies 70.

**Architecture:** A small parser in `calc.js` (no `eval`) is inlined into the card page when a
screen asks for it (`screen.calc = true`, set only by the palette). The page keeps one hidden
calculator row first in the list and shows it while the typed text is a whole expression.
Enter sends `calc:<result>`; the palette feature copies it.

**Tech Stack:** JavaScript in the card's WebKit page (tested with node), Hammerspoon Lua (luajit tests).

**Spec:** `docs/superpowers/specs/2026-11-13-mic-mute-and-calculator-design.md` (part 2)

## Global Constraints

- Operators `+ - * / % ^`, brackets, decimals, unary minus; `^` binds right; `%` is remainder.
- Never `eval` or `Function`: typed text can't run as code.
- A lone number or anything that isn't a whole expression shows no row.
- Number format: integers that are safe show whole; others round to 10 significant digits with trailing zeros trimmed. Non-finite results (division by zero, overflow) show no row.
- Row: label `= <result>`, hint `Enter copies`; Enter copies the result and closes the palette.
- `calc.js` sits beside `card.lua` in `hammerspoon/.hammerspoon/`: a new top-level file, so stow must run again before reload (`~/.hammerspoon` links per file). `card.lua` must still load when `calc.js` is missing: the palette then just has no calculator.

## Review Focus

1. Typing a window title or app name that contains digits, such as `omv-14` or `Zoom 2`: no calculator row, and filtering is unchanged.
2. Typing a single workspace number such as `1` to filter windows: no calculator row.
3. An expression that is also text other rows match, such as `1-2`: the calculator row is first and selected, other matches follow.
4. Backspacing an expression back to text: the row disappears, and the selection doesn't stick to a hidden row.
5. `calc.js` missing (not yet stowed): the palette opens and filters as before.

---

### Task 1: The parser (`calc.js`)

**Files:**
- Create: `hammerspoon/.hammerspoon/calc.js`
- Test: `tests/calc_test.mjs`, `tests/calc_test.sh` (node; skip with `ok - skipped` when node is missing, as `agent_plugins_test.sh` does)

**Interfaces:**
- Produces: global `omvCalc(text: string) -> string | null`; also `module.exports = omvCalc` when `module` exists, so node can `require` it.

- [ ] **Step 1: Write the failing tests** (`calc(text) === expected`):
  - should multiply when typed `2*35` → `"70"`
  - should multiply before adding: `2+3*4` → `"14"`
  - should work out brackets first: `(2+3)*4` → `"20"`
  - should raise to a power from the right: `2^3^2` → `"512"`
  - should take a remainder with %: `10%3` → `"1"`
  - should read decimals: `1.5*2` → `"3"`
  - should read a leading minus: `-3+5` → `"2"`
  - should ignore spaces: `" 2 * 35 "` → `"70"`
  - should round to 10 significant digits: `1/3` → `"0.3333333333"`
  - should trim trailing zeros: `0.1+0.2` → `"0.3"`
  - should show a large whole number in full: `2^40` → `"1099511627776"`
  - should give nothing for a lone number: `42` → `null`
  - should give nothing for text with digits: `omv-14`, `2 apples` → `null`
  - should give nothing for an unfinished expression: `2*`, `(2+3` → `null`
  - should give nothing when dividing by zero: `1/0` → `null`
  - should give nothing when the result overflows: `10^400` → `null`
  - should never run code: `alert(1)`, `2*constructor` → `null`
- [ ] **Step 2: Run `bash tests/calc_test.sh`** — expect FAIL: `calc.js` not found.
- [ ] **Step 3: Implement `omvCalc`** as a recursive-descent parser over a tokenizer of numbers, the six operators and brackets.
- [ ] **Step 4: Run `bash tests/calc_test.sh`** — expect all `ok`.
- [ ] **Step 5: Commit** `feat: add a calculator parser`

### Task 2: The calculator row in the palette

**Files:**
- Modify: `hammerspoon/.hammerspoon/card.lua` (`card.html`, the page script's `draw()`)
- Modify: `hammerspoon/.hammerspoon/palette.lua` (`palette.parse`)
- Modify: `hammerspoon/.hammerspoon/features/windows.lua` (`feature.toggle`'s screen, `onPaletteMessage`)
- Modify: `docs/shots.lua` (the palette shot gets `calc = true`)
- Test: `tests/palette_test.lua`

**Interfaces:**
- Consumes: Task 1's `omvCalc`.
- Produces: `screen.calc` (bool) for `card.html`; row id `calc:<result>`; `palette.parse("calc:70") -> "calc", "70"`.

- [ ] **Step 1: Write the failing tests** in `tests/palette_test.lua`:
  - should read a calculator row's result → `palette.parse("calc:70")` gives `"calc", "70"`
  - should keep a decimal result whole → `palette.parse("calc:0.3333333333")` gives `"calc", "0.3333333333"`
  - should add the calculator to a card that asks for it → `card.html({ prompt = "x", rows = {}, calc = true })` contains `data-calc` and `omvCalc`
  - should leave the calculator out of other cards → `card.html({ prompt = "x", rows = {} })` contains neither
- [ ] **Step 2: Run `bash tests/palette_test.sh`** — expect the four to FAIL.
- [ ] **Step 3: Implement:**
  - `card.lua` reads `calc.js` from its own folder once (`debug.getinfo(1, "S").source`), `""` when missing. With `screen.calc`, `card.html` adds `data-calc` to `body`, a first row `<div class="row calc hidden" data-id="calc:">` with `.label` and `.hint`, and the parser before the page script.
  - In `draw()`, after filtering: when `data-calc` is set, `omvCalc(query)` shows the calc row with label `= <result>`, hint `Enter copies` and id `calc:<result>`, or hides it. Selection is clamped after, as now.
  - `palette.parse` returns `"calc", value` for `calc:`.
  - `features/windows.lua`: the palette screen gets `calc = true`; `onPaletteMessage` for `calc` puts the value on the clipboard (`hs.pasteboard.setContents`), alerts `Copied <value>` for 1s, and closes.
  - `docs/shots.lua`: the palette shot's screen gets `calc = true` (no visible change: the row is hidden until typed).
- [ ] **Step 4: Run `bash tests/run.sh`** — expect exit 0.
- [ ] **Step 5: Restow and verify by hand:** `stow --dir=. --target=$HOME --restow hammerspoon`, reload Hammerspoon, open Option+Space, type `2*35`: top row `= 70` selected; Enter → clipboard holds `70`. Type `omv-14` and `1`: no calculator row. Type `2*35` then Backspace three times: the row goes, the selection lands on a shown row. (Review Focus 1, 2, 4.)
- [ ] **Step 6: Commit** `feat: work out sums in the palette`

### Task 3: README

**Files:**
- Modify: `README.md` (the Palette section)

- [ ] **Step 1: Write it:** typing a sum shows its result first; `+ - * / % ^`, brackets, decimals; Enter copies it.
- [ ] **Step 2: Run `bash tests/shots_test.sh`** — expect all `ok`.
- [ ] **Step 3: Commit** `docs: describe the palette calculator`
