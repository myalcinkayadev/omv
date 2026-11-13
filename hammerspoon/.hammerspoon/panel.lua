-- The status-card layout shared by the Wi-Fi, Ethernet, Battery and Disk cards: an icon, a title
-- and a status line, a big number on the right, a bar, a grid of label/value pairs, then
-- buttons, or a list of choices with a size and an age each.
-- Left and Right, or Up and Down, move between the choices, Enter or a click presses one,
-- Escape closes.
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
  /* A bar of several shares, such as used and purgeable space, each in its own shade. */
  .track.stack { display: flex; overflow: hidden; }
  .track.stack i { border-radius: 0; flex: none; }
  .track.stack .purgeable, .swatch.purgeable::after { background: #7a7a7a; }
  .swatch::after { content: ""; display: inline-block; width: 8px; height: 8px; border-radius: 2px;
    margin-left: 8px; vertical-align: 1px; }
  .sec { border-top: 1px solid #2a2a2a; margin-top: 18px; padding-top: 16px; color: #7a7a7a;
    letter-spacing: 1px; font-size: 13px; }
  .btns { display: flex; gap: 12px; margin-top: 12px; }
  /* Buttons share the row equally and keep to one line, so a row of three stays even. */
  .btn { flex: 1 1 0; min-width: 0; border: 1px solid #8d8d8d; padding: 10px 4px; text-align: center; font-size: 14px;
    cursor: default; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .btn.selected { background: #333; }
  /* The list: one choice a line, its size and age in columns on the right. */
  .btns.list { display: block; margin-top: 10px; }
  .btns.list .item { display: flex; align-items: center; height: 40px; padding: 0 12px; border: 0;
    border-radius: 4px; text-align: left; font-size: 15px; }
  .item .icon { width: 28px; font-size: 17px; }
  .item .label { flex: 1; overflow: hidden; text-overflow: ellipsis; }
  .item .age { width: 64px; text-align: right; color: #7a7a7a; font-size: 13px; }
  .btns.list .item.selected { background: #fff; color: #000; }
  .item.selected .age { color: #3a3a3a; }
]]

panel.SCRIPT = [[
  const buttons = () => Array.from(document.querySelectorAll(".btn"));
  const send = (type, id) => window.webkit.messageHandlers.omv.postMessage({ type, id: id || "" });
  let selected = Math.max(0, buttons().findIndex((button) => button.classList.contains("selected")));
  const draw = () => buttons().forEach((button, index) => button.classList.toggle("selected", index === selected));
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") return send("close");
    const all = buttons();
    if (!all.length) return;
    if (event.key === "ArrowRight" || event.key === "ArrowDown") selected = (selected + 1) % all.length;
    else if (event.key === "ArrowLeft" || event.key === "ArrowUp") selected = (selected - 1 + all.length) % all.length;
    else if (event.key === "Enter") return send("choose", all[selected].dataset.id);
    else return;
    event.preventDefault();
    draw();
  });
  // One listener on the row, so buttons replaced by an update still answer clicks.
  document.querySelector(".btns")?.addEventListener("click", (event) => {
    const button = event.target.closest(".btn");
    if (button) send("choose", button.dataset.id);
  });
  // Hammerspoon's update while the card is open: new values, the same selected button.
  window.omvUpdate = (data, row) => {
    document.querySelector(".data").innerHTML = data;
    const btns = document.querySelector(".btns");
    if (btns) btns.innerHTML = row;
    selected = Math.min(selected, Math.max(0, buttons().length - 1));
    draw();
  };
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

-- segments = { { share, kind } }: one bar split into shares of 100, drawn in order.
function panel.stack(segments)
  local parts = {}
  for _, segment in ipairs(segments) do
    parts[#parts + 1] = '<i class="' .. card.escape(segment.kind) .. '" style="width: ' .. segment.share .. '%"></i>'
  end
  return '<div class="track stack">' .. table.concat(parts) .. "</div>"
end

-- pairs = { { label, value, swatch } }, laid out two to a row. A swatch names the bar
-- segment the label stands for, and shows its shade beside it.
function panel.grid(pairs)
  local cells = {}
  for _, pair in ipairs(pairs) do
    local label = pair[3] and ('<span class="swatch ' .. card.escape(pair[3]) .. '">') or "<span>"
    cells[#cells + 1] = label .. card.escape(pair[1]) .. "</span><b>" .. card.escape(pair[2]) .. "</b>"
  end
  return "<div class=grid>" .. table.concat(cells) .. "</div>"
end

-- buttons = { { id, icon, label, selected } }. The selected one starts highlighted, and
-- the first one when none is.
function panel.buttonsRow(buttons)
  local parts = {}
  for _, button in ipairs(buttons) do
    parts[#parts + 1] = '<div class="btn' .. (button.selected and " selected" or "") .. '" data-id="' .. card.escape(button.id) .. '">'
      .. card.escape(button.icon) .. "&nbsp;" .. card.escape(button.label) .. "</div>"
  end
  return table.concat(parts)
end

-- items = { { id, icon, label, size, age } }: the list's lines. The first one starts selected.
function panel.listRows(items)
  local parts = {}
  for index, item in ipairs(items) do
    parts[#parts + 1] = '<div class="btn item' .. (index == 1 and " selected" or "") .. '" data-id="' .. card.escape(item.id) .. '">'
      .. "<span class=icon>" .. card.escape(item.icon) .. "</span><span class=label>" .. card.escape(item.label) .. "</span>"
      .. "<span class=size>" .. card.escape(item.size or "") .. "</span><span class=age>" .. card.escape(item.age or "") .. "</span></div>"
  end
  return table.concat(parts)
end

local function choices(model)
  return model.list and panel.listRows(model.buttons) or panel.buttonsRow(model.buttons)
end

function panel.buttons(model)
  return "<div class=sec>" .. card.escape(model.section or "ACTIONS") .. '</div><div class="btns' .. (model.list and " list" or "") .. '">'
    .. choices(model) .. "</div>"
end

-- The part of the card that changes: the head, the bar and the grid, without the buttons.
function panel.data(model)
  local bar = model.segments and panel.stack(model.segments) or panel.track(model.percent)
  return panel.head(model.icon, model.title, model.sub, model.big) .. bar .. panel.grid(model.grid)
end

-- model = { icon, title, sub, big, percent or segments, grid, buttons, section, list }
function panel.html(model)
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. panel.STYLE .. "</style><body>"
    .. "<div class=data>" .. panel.data(model) .. "</div>"
    .. panel.buttons(model)
    .. "<script>" .. panel.SCRIPT .. "</script></body>"
end

-- The JavaScript that updates an open card to model, keeping its selected button.
function panel.update(model)
  return "omvUpdate(" .. card.jsString(panel.data(model)) .. "," .. card.jsString(choices(model)) .. ")"
end

return panel
