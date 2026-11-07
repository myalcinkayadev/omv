-- Renders the Omarchy-style card shared by the system menu and the key list: a search
-- prompt on top, then rows to pick from. Typing filters the rows. Up and Down move,
-- Enter or Right picks, Left or Backspace on an empty search goes back, Escape closes.
-- Picks reach init.lua through the "omv" message handler as { type, id }.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = {}

card.STYLE = [[
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; background: #000; color: #fff; overflow: hidden;
    font: 15px "JetBrainsMono Nerd Font Propo", "JetBrainsMono Nerd Font Mono", monospace; }
  body { border: 2px solid #8d8d8d; padding: 14px; display: flex; flex-direction: column; }
  .prompt { font-size: 17px; padding: 6px 10px 12px; white-space: pre; }
  .prompt.empty::before { content: attr(data-prompt); }
  .caret { display: inline-block; width: 8px; height: 18px; background: #fff; vertical-align: -3px; margin-left: 1px; }
  .rows { overflow-y: auto; flex: 1; scrollbar-width: none; }
  .rows::-webkit-scrollbar { display: none; }
  .row { display: flex; align-items: center; height: 44px; padding: 0 12px; border-radius: 4px; color: #d0d0d0; cursor: default; }
  .row .icon { width: 28px; font-size: 18px; }
  .row .label { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .row .hint { color: #7a7a7a; padding-left: 16px; white-space: nowrap; }
  .row.selected { background: #fff; color: #000; }
  .row.selected .hint { color: #3a3a3a; }
  .row.hidden { display: none; }
  body.compact .row { height: 30px; }
  body.compact .row .label { color: #fff; }
  body.compact .row.selected .label { color: #000; }
  .none { color: #7a7a7a; padding: 8px 12px; display: none; }
  .rows.columns { overflow: hidden; column-gap: 28px; column-fill: auto; }
  .rows.columns .row { break-inside: avoid; }
]]

local SCRIPT = [[
  const rows = Array.from(document.querySelectorAll(".row"));
  const prompt = document.querySelector(".prompt");
  const text = document.querySelector(".text");
  const none = document.querySelector(".none");
  let query = "";
  // An input card has no rows to pick: Enter sends what was typed.
  const takesInput = document.body.dataset.input !== undefined;
  let selected = Math.max(0, Number(document.body.dataset.selected || 1) - 1);

  const send = (type, id) => window.webkit.messageHandlers.omv.postMessage({ type, id: id || "" });
  const visible = () => rows.filter((row) => !row.classList.contains("hidden"));

  function draw() {
    const words = query.toLowerCase().split(/\s+/).filter(Boolean);
    rows.forEach((row) => {
      const haystack = row.textContent.toLowerCase();
      row.classList.toggle("hidden", !words.every((word) => haystack.includes(word)));
    });
    const shown = visible();
    selected = Math.min(selected, Math.max(0, shown.length - 1));
    rows.forEach((row) => row.classList.remove("selected"));
    if (shown[selected]) {
      shown[selected].classList.add("selected");
      shown[selected].scrollIntoView({ block: "nearest" });
    }
    none.style.display = shown.length && !takesInput ? "none" : "block";
    text.textContent = query;
    prompt.classList.toggle("empty", query === "");
  }

  function pick(row) {
    if (row) send("choose", row.dataset.id);
  }

  document.addEventListener("keydown", (event) => {
    const shown = visible();
    if (event.key === "Escape") return send("close");
    if (event.key === "ArrowDown" || (event.ctrlKey && event.key === "n")) selected = (selected + 1) % Math.max(1, shown.length);
    else if (event.key === "ArrowUp" || (event.ctrlKey && event.key === "p")) selected = (selected - 1 + shown.length) % Math.max(1, shown.length);
    else if (event.key === "Enter" && takesInput) return send("submit", query);
    else if (event.key === "Enter" || event.key === "ArrowRight") return pick(shown[selected]);
    else if (event.key === "ArrowLeft" || (event.key === "Backspace" && query === "")) return send("back");
    else if (event.key === "Backspace") query = query.slice(0, -1);
    else if (event.key.length === 1 && !event.metaKey && !event.ctrlKey) { query += event.key; selected = 0; }
    else return;
    event.preventDefault();
    draw();
  });

  // WebKit reports a move when the card appears under a still pointer, so hover only
  // selects once the pointer has really moved.
  let pointer = null;
  rows.forEach((row) => {
    row.addEventListener("mousemove", (event) => {
      const at = event.screenX + "," + event.screenY;
      if (pointer === null || pointer === at) { pointer = at; return; }
      pointer = at;
      selected = visible().indexOf(row);
      draw();
    });
    row.addEventListener("click", () => pick(row));
  });

  draw();
]]

function card.escape(text)
  return (tostring(text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function rowHtml(row)
  local icon = row.icon and ("<span class=icon>" .. card.escape(row.icon) .. "</span>") or ""
  local hint = row.submenu and "›" or row.hint
  return '<div class="row" data-id="' .. card.escape(row.id) .. '"'
    .. (row.submenu and " data-submenu" or "") .. ">"
    .. icon
    .. "<span class=label>" .. card.escape(row.label) .. "</span>"
    .. (hint and ("<span class=hint>" .. card.escape(hint) .. "</span>") or "")
    .. "</div>"
end

-- Several columns show every row at once, instead of scrolling one long list.
local function rowsOpen(columns)
  if not columns or columns <= 1 then return "<div class=rows>" end
  return '<div class="rows columns" style="column-count: ' .. columns .. '">'
end

-- screen = { prompt = "System…", rows = { { id, icon, label, hint, submenu } },
--            selected = 1, compact = false, columns = 1, input = false, hint = "" }
-- An input card sends what was typed on Enter, and shows its hint under the prompt.
function card.html(screen)
  local rows = {}
  for _, row in ipairs(screen.rows) do rows[#rows + 1] = rowHtml(row) end
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. "</style>"
    .. '<body class="' .. (screen.compact and "compact" or "") .. '" data-selected="' .. (screen.selected or 1) .. '"'
    .. (screen.input and " data-input" or "") .. ">"
    .. '<div class="prompt empty" data-prompt="' .. card.escape(screen.prompt) .. '"><span class=text></span><span class=caret></span></div>'
    .. rowsOpen(screen.columns) .. table.concat(rows) .. "<div class=none>" .. card.escape(screen.hint or "No matches") .. "</div></div>"
    .. "<script>" .. SCRIPT .. "</script></body>"
end

return card
