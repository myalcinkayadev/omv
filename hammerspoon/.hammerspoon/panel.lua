-- The status-card layout shared by the Wi-Fi, Ethernet and Battery cards: an icon, a title and a
-- status line, a big number on the right, a bar, a grid of label/value pairs, then buttons.
-- Left and Right move between the buttons, Enter or a click presses one, Escape closes.
-- Presses reach init.lua through the "omv" message handler as { type = "choose", id }.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = require("card")

local panel = {}

panel.STYLE = [[
  body { padding: 22px 24px; display: block; }
  .head { display: flex; align-items: flex-start; gap: 16px; }
  .head .icon { font-size: 26px; width: 28px; text-align: center; padding-top: 2px; }
  .head .title { font-size: 18px; }
  .head .sub { color: #7a7a7a; letter-spacing: 2px; font-size: 13px; margin-top: 4px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 260px; }
  .head .big { margin-left: auto; font-size: 38px; line-height: 1; white-space: nowrap; }
  .head .big small { font-size: 16px; color: #7a7a7a; }
  .track { height: 10px; background: #2a2a2a; border-radius: 5px; margin: 22px 0 18px; }
  .track i { display: block; height: 10px; border-radius: 5px; background: #fff; }
  .grid { display: grid; grid-template-columns: auto 1fr auto auto; column-gap: 14px; row-gap: 10px;
    color: #7a7a7a; font-size: 14px; white-space: nowrap; }
  .grid b { color: #fff; font-weight: normal; text-align: right; white-space: nowrap; }
  .sec { border-top: 1px solid #2a2a2a; margin-top: 18px; padding-top: 16px; color: #7a7a7a;
    letter-spacing: 1px; font-size: 13px; }
  .btns { display: flex; gap: 12px; margin-top: 12px; }
  .btn { flex: 1; border: 1px solid #8d8d8d; padding: 10px; text-align: center; font-size: 14px; cursor: default; }
  .btn.selected { background: #333; }
]]

panel.SCRIPT = [[
  const buttons = Array.from(document.querySelectorAll(".btn"));
  const send = (type, id) => window.webkit.messageHandlers.omv.postMessage({ type, id: id || "" });
  let selected = Math.max(0, buttons.findIndex((button) => button.classList.contains("selected")));
  const draw = () => buttons.forEach((button, index) => button.classList.toggle("selected", index === selected));
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") return send("close");
    if (!buttons.length) return;
    if (event.key === "ArrowRight") selected = (selected + 1) % buttons.length;
    else if (event.key === "ArrowLeft") selected = (selected - 1 + buttons.length) % buttons.length;
    else if (event.key === "Enter") return send("choose", buttons[selected].dataset.id);
    else return;
    event.preventDefault();
    draw();
  });
  buttons.forEach((button) => button.addEventListener("click", () => send("choose", button.dataset.id)));
  draw();
]]

-- big may carry a unit after a space, shown smaller: "1 Gb/s" shows "1" big and "Gb/s" small.
function panel.head(icon, title, sub, big)
  local number, unit = tostring(big):match("^(%S+) (.+)$")
  local bigHtml = number and (card.escape(number) .. "<small> " .. card.escape(unit) .. "</small>") or card.escape(big)
  return "<div class=head><div class=icon>" .. card.escape(icon) .. "</div>"
    .. "<div><div class=title>" .. card.escape(title) .. "</div><div class=sub>" .. card.escape(sub) .. "</div></div>"
    .. "<div class=big>" .. bigHtml .. "</div></div>"
end

function panel.track(percent)
  return '<div class=track><i style="width: ' .. percent .. '%"></i></div>'
end

-- pairs = { { label, value } }, laid out two to a row.
function panel.grid(pairs)
  local cells = {}
  for _, pair in ipairs(pairs) do
    cells[#cells + 1] = "<span>" .. card.escape(pair[1]) .. "</span><b>" .. card.escape(pair[2]) .. "</b>"
  end
  return "<div class=grid>" .. table.concat(cells) .. "</div>"
end

-- buttons = { { id, icon, label, selected } }. The selected one starts highlighted, and
-- the first one when none is.
function panel.buttons(buttons, title)
  local parts = {}
  for _, button in ipairs(buttons) do
    parts[#parts + 1] = '<div class="btn' .. (button.selected and " selected" or "") .. '" data-id="' .. card.escape(button.id) .. '">'
      .. card.escape(button.icon) .. "&nbsp; " .. card.escape(button.label) .. "</div>"
  end
  return "<div class=sec>" .. card.escape(title or "ACTIONS") .. "</div><div class=btns>" .. table.concat(parts) .. "</div>"
end

-- model = { icon, title, sub, big, percent, grid, buttons, section }
function panel.html(model)
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. panel.STYLE .. "</style><body>"
    .. panel.head(model.icon, model.title, model.sub, model.big)
    .. panel.track(model.percent)
    .. panel.grid(model.grid)
    .. panel.buttons(model.buttons, model.section)
    .. "<script>" .. panel.SCRIPT .. "</script></body>"
end

return panel
