# Mic mute and palette calculator

Two small, separate changes, built one at a time: mic mute first.

## 1. Mute the mic from anywhere

**Why:** meetings are joined from the bar, but each meeting app has its own mute key that
only works while its window has focus. One key should mute the mic whatever is in front.

**What:**
- Option+M toggles the mic. Every Option+Shift letter is taken (Option+Shift+X is Disk);
  Option+M is free in AeroSpace and init.lua.
- A red mic shows in the bar only while muted; a click on it unmutes.
- Muting stays with "the mic", not one device: when the input device changes while muted,
  such as AirPods connecting, the new device is muted too, so the indicator never lies.
- A row in the Sound card and the key list.

**Approaches:**
- Device mute (`hs.audiodevice:setInputMuted`): clean, and other apps see a muted device.
  Some USB and Bluetooth mics don't support it.
- Input volume to 0, restored on unmute: works on every device, but a slider elsewhere can
  undo it, and the level to restore has to be remembered.
- Picked: device mute, falling back to input volume 0 when the device refuses mute. The
  Sound card already sets input volume, so the fallback reuses that path.

**Non-goals:** push-to-talk; muting the meeting app's own mute; muting outputs.

## 2. Calculator in the palette

**Why:** quick sums without opening Calculator.

**What:**
- Typing an expression such as `2*35` in Option+Space shows a top row `= 70`, with
  "Enter copies" as its hint; the other rows keep filtering as before.
- `+ - * / % ^`, brackets and decimals. A small parser, never `eval`, so typed text can't
  run as code. Text that isn't a whole expression shows no row.
- Enter on that row copies the result to the clipboard and closes the palette.

**Approaches:**
- In the card's page, on every keystroke: instant, as the filtering already is.
- In Hammerspoon, asked on every keystroke: testable in Lua, but a round trip per key.
- Picked: in the page. The parser lives in its own `calc.js`, inlined into the card and
  tested with Node, as `tests/agent_plugins_test.mjs` already tests JavaScript.

**Non-goals:** units, currency, variables, history.

## Left to the builder

The bar item's name and place, the mic glyphs, and the exact number format (how many
decimals; I'd trim trailing zeros and round to 10 significant digits).
