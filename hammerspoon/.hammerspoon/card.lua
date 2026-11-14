-- Renders the Omarchy-style card shared by the system menu and the key list: a search
-- prompt on top, then rows to pick from. Typing filters the rows. Up and Down move,
-- Enter or Right picks, Left or Backspace on an empty search goes back, Escape closes.
-- In a card with columns, Left and Right move between columns instead, so only Enter picks.
-- Picks reach init.lua through the "omv" message handler as { type, id }.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = {}

-- The palette's calculator, read from beside this file. Empty when calc.js is missing, such
-- as before stow links it: the palette then filters as before, with no calculator row.
local function readCalc()
  local folder = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
  local file = io.open(folder .. "calc.js", "r")
  if not file then return "" end
  local text = file:read("*a")
  file:close()
  return text
end

local CALC = readCalc()

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
  .thumb { width: 20px; height: 20px; object-fit: cover; vertical-align: middle; border: 1px solid #2a2a2a; }
  .row .label { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .row .hint { color: #9a9a9a; padding-left: 16px; white-space: nowrap; }
  .row.selected { background: #fff; color: #000; }
  .row.selected .hint { color: #3a3a3a; }
  .row.hidden { display: none; }
  .note { display: flex; align-items: center; height: 44px; padding: 0 12px; color: #7a7a7a; }
  .note .icon { width: 28px; font-size: 18px; }
  .note .label { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  body.compact .note { height: 30px; }
  body.compact .row { height: 30px; }
  body.compact .row .label { color: #fff; }
  body.compact .row.selected .label { color: #000; }
  .none { color: #7a7a7a; padding: 8px 12px; display: none; }
  .rows.columns { overflow: hidden; column-gap: 28px; column-fill: auto; }
  .rows.columns .row { break-inside: avoid; }
  .group { height: 30px; line-height: 30px; padding: 0 12px; color: #8d8d8d; font-size: 12px;
    text-transform: uppercase; letter-spacing: 1px; }
  .lead { break-inside: avoid; }
  .group.hidden { display: none; }
]]

local SCRIPT = [[
  // Read again when file search adds rows.
  let rows = Array.from(document.querySelectorAll(".row"));
  let groups = Array.from(document.querySelectorAll(".group"));
  // Side by side columns: Left and Right move between columns, and only Enter picks.
  const inColumns = document.querySelector(".rows.columns") !== null;
  const prompt = document.querySelector(".prompt");
  const text = document.querySelector(".text");
  const none = document.querySelector(".none");
  let query = "";
  // An input card has no rows to pick: Enter sends what was typed.
  const takesInput = document.body.dataset.input !== undefined;
  let selected = Math.max(0, Number(document.body.dataset.selected || 1) - 1);

  const send = (type, id) => window.webkit.messageHandlers.omv.postMessage({ type, id: id || "" });
  const visible = () => rows.filter((row) => !row.classList.contains("hidden"));
  // The calculator row, first in the list: shown while the search is a whole sum.
  const calc = typeof omvCalc === "function" ? document.querySelector(".row.calc") : null;
  // File search, on in a card with data-files: after a pause in typing, Hammerspoon is asked
  // for files matching the text, and its answer fills .files through omvFiles.
  const files = document.body.dataset.files !== undefined ? document.querySelector(".files") : null;
  const FILES_PAUSE_MS = 300, FILES_MIN_LENGTH = 3;
  let filesTimer = null;

  // Called from Hammerspoon to update a row's hint while the card stays open.
  window.omvSetHint = (id, value) => {
    const row = rows.find((candidate) => candidate.dataset.id === id);
    if (!row) return;
    let hint = row.querySelector(".hint");
    if (!value) { if (hint) hint.remove(); return; }
    if (!hint) { hint = document.createElement("span"); hint.className = "hint"; row.appendChild(hint); }
    hint.textContent = value;
  };

  function draw() {
    const words = query.toLowerCase().split(/\s+/).filter(Boolean);
    rows.forEach((row) => {
      if (row === calc) return;
      const haystack = ((row.dataset.group || "") + " " + (row.dataset.keywords || "") + " " + row.textContent).toLowerCase();
      row.classList.toggle("hidden", !words.every((word) => haystack.includes(word)));
    });
    if (calc) {
      const result = omvCalc(query);
      calc.classList.toggle("hidden", result === null);
      calc.dataset.id = "calc:" + (result || "");
      calc.querySelector(".label").textContent = "= " + (result || "");
    }
    groups.forEach((group) => {
      const name = group.dataset.name;
      group.classList.toggle("hidden", !rows.some((row) => row.dataset.group === name && !row.classList.contains("hidden")));
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

  // The row in the next column over, level with the selected one.
  function sideways(step) {
    const shown = visible();
    if (!shown[selected]) return;
    const from = shown[selected].getBoundingClientRect();
    const across = shown.filter((row) => {
      const box = row.getBoundingClientRect();
      return step > 0 ? box.left > from.right : box.right < from.left;
    });
    if (!across.length) return;
    const lefts = across.map((row) => row.getBoundingClientRect().left);
    const edge = step > 0 ? Math.min(...lefts) : Math.max(...lefts);
    const column = across.filter((row) => row.getBoundingClientRect().left === edge);
    const distance = (row) => Math.abs(row.getBoundingClientRect().top - from.top);
    selected = shown.indexOf(column.reduce((best, row) => (distance(row) < distance(best) ? row : best)));
  }

  function pick(row) {
    if (row) send("choose", row.dataset.id);
  }

  // WebKit reports a move when the card appears under a still pointer, so hover only
  // selects once the pointer has really moved.
  let pointer = null;
  function wire(row) {
    row.addEventListener("mousemove", (event) => {
      const at = event.screenX + "," + event.screenY;
      if (pointer === null || pointer === at) { pointer = at; return; }
      pointer = at;
      selected = visible().indexOf(row);
      draw();
    });
    row.addEventListener("click", () => pick(row));
  }

  function collect() {
    rows = Array.from(document.querySelectorAll(".row"));
    groups = Array.from(document.querySelectorAll(".group"));
  }

  // The files found for older text go at once; new ones are asked for after a pause.
  function askFiles() {
    if (!files) return;
    clearTimeout(filesTimer);
    if (files.innerHTML !== "") { files.innerHTML = ""; collect(); }
    if (query.trim().length < FILES_MIN_LENGTH) return;
    const asked = query;
    filesTimer = setTimeout(() => send("files", asked), FILES_PAUSE_MS);
  }

  // Called from Hammerspoon with the rows found for text. An answer for text that's no longer
  // typed is dropped. The selected row stays selected when it's still shown.
  window.omvFiles = (asked, html) => {
    if (!files || asked !== query) return;
    const was = visible()[selected];
    files.innerHTML = html;
    collect();
    files.querySelectorAll(".row").forEach(wire);
    draw();
    const at = visible().indexOf(was);
    if (at >= 0 && at !== selected) { selected = at; draw(); }
  };

  document.addEventListener("keydown", (event) => {
    const shown = visible();
    const typed = query;
    if (event.key === "Escape") return send("close");
    // A card that asks for Tab, such as the process card switching its sort, hears it.
    if (event.key === "Tab" && document.body.dataset.tab !== undefined) { event.preventDefault(); return send("tab"); }
    if (event.key === "ArrowDown" || (event.ctrlKey && event.key === "n")) selected = (selected + 1) % Math.max(1, shown.length);
    else if (event.key === "ArrowUp" || (event.ctrlKey && event.key === "p")) selected = (selected - 1 + shown.length) % Math.max(1, shown.length);
    else if (event.key === "Enter" && takesInput) return send("submit", query);
    else if (inColumns && event.key === "ArrowRight") sideways(1);
    else if (inColumns && event.key === "ArrowLeft") sideways(-1);
    else if (event.key === "Enter" || event.key === "ArrowRight") return pick(shown[selected]);
    else if (event.key === "ArrowLeft" || (event.key === "Backspace" && query === "")) return send("back");
    else if (event.key === "Backspace") query = query.slice(0, -1);
    else if (event.key.length === 1 && !event.metaKey && !event.ctrlKey) { query += event.key; selected = 0; }
    else return;
    event.preventDefault();
    if (query !== typed) askFiles();
    draw();
  });

  rows.forEach(wire);

  draw();
]]

-- Text as a JavaScript string literal, for updating an open card in place. "</" is broken
-- up, so the text can never close the page's script.
function card.jsString(text)
  local escaped = tostring(text or ""):gsub('[\\"\n\r\t]', { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" })
  return '"' .. escaped:gsub("</", "<\\/") .. '"'
end

-- The JavaScript that sets the hints of an open list card's rows in place, from
-- { [row id] = text }, keeping its selection and what was typed. false clears a hint.
function card.setHints(hints)
  local calls = {}
  for id, text in pairs(hints) do
    calls[#calls + 1] = "omvSetHint(" .. card.jsString(id) .. "," .. card.jsString(text or "") .. ");"
  end
  return table.concat(calls)
end

function card.escape(text)
  return (tostring(text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function rowHtml(row)
  local icon = row.icon and ("<span class=icon>" .. card.escape(row.icon) .. "</span>") or ""
  -- A picture, such as a copied image's preview, takes the icon's place.
  if row.image then icon = '<span class=icon><img class=thumb src="' .. card.escape(row.image) .. '" alt=""></span>' end
  -- A note is only text: without the row class, keys, the pointer and Enter pass it by.
  if row.note then
    return "<div class=note>" .. icon .. "<span class=label>" .. card.escape(row.label) .. "</span></div>"
  end
  local hint = row.submenu and "›" or row.hint
  return '<div class="row" data-id="' .. card.escape(row.id) .. '"'
    .. (row.group and (' data-group="' .. card.escape(row.group) .. '"') or "")
    .. (row.keywords and (' data-keywords="' .. card.escape(row.keywords) .. '"') or "")
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

-- A header line above each run of rows that share a group. WebKit ignores break-after
-- in columns, so the header and the group's first row share an unbreakable box, which
-- keeps a header from sitting alone at the foot of a column.
local function rowsWithHeaders(screenRows)
  local lines, previous = {}, nil
  for _, row in ipairs(screenRows) do
    local line = rowHtml(row)
    if row.group and row.group ~= previous then
      line = '<div class=lead><div class=group data-name="' .. card.escape(row.group) .. '">'
        .. card.escape(row.group) .. "</div>" .. line .. "</div>"
    end
    previous = row.group
    lines[#lines + 1] = line
  end
  return lines
end

-- screen = { prompt = "System…", rows = { { id, icon, label, hint, submenu, group, note } },
--            selected = 1, compact = false, columns = 1, input = false, hint = "" }
-- An input card sends what was typed on Enter, and shows its hint under the prompt.
-- A card with calc = true, such as the palette, works out a typed sum in its first row.
function card.html(screen)
  local rows = rowsWithHeaders(screen.rows)
  local calc = screen.calc and CALC ~= ""
  if calc then
    table.insert(rows, 1, '<div class="row calc hidden" data-id="calc:"><span class=icon>󰃬</span>'
      .. "<span class=label></span><span class=hint>Enter copies</span></div>")
  end
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. "</style>"
    .. '<body class="' .. (screen.compact and "compact" or "") .. '" data-selected="' .. (screen.selected or 1) .. '"'
    .. (screen.input and " data-input" or "") .. (screen.tab and " data-tab" or "") .. (calc and " data-calc" or "") .. (screen.files and " data-files" or "") .. ">"
    .. '<div class="prompt empty" data-prompt="' .. card.escape(screen.prompt) .. '"><span class=text></span><span class=caret></span></div>'
    .. rowsOpen(screen.columns) .. table.concat(rows) .. (screen.files and "<div class=files></div>" or "") .. "<div class=none>" .. card.escape(screen.hint or "No matches") .. "</div></div>"
    .. (calc and ("<script>" .. CALC .. "</script>") or "")
    .. "<script>" .. SCRIPT .. "</script></body>"
end

-- The JavaScript that hands an open palette the file rows found for text. The page drops
-- them when other text is typed by then.
function card.filesCall(text, fileRows)
  return "omvFiles(" .. card.jsString(text) .. "," .. card.jsString(table.concat(rowsWithHeaders(fileRows))) .. ");"
end

-- The large card for Pomodoro breaks: the whole screen dims, and a wider card sits in
-- the middle with a headline, or a countdown the page ticks itself. Up and Down move,
-- Enter picks, and a row's letter key picks it at once. Escape is left to init.lua, which decides what it means on each card.
local BIG_STYLE = [[
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; color: #fff; overflow: hidden;
    font: 16px "JetBrainsMono Nerd Font Propo", "JetBrainsMono Nerd Font Mono", monospace; }
  body.big { background: rgba(0, 0, 0, 0.72); display: flex; align-items: center; justify-content: center; }
  .card { width: 560px; background: #000; border: 2px solid #8d8d8d; padding: 30px 30px 22px; }
  .kicker { color: #7a7a7a; font-size: 14px; letter-spacing: 0.5px; margin-bottom: 10px; }
  .dots { display: flex; flex-wrap: wrap; gap: 8px; width: 72px; margin-bottom: 22px; }
  .dots b { width: 10px; height: 10px; border-radius: 50%; background: #3a3a3a; }
  .dots b.on { background: #fff; }
  .title { font-size: 30px; margin: 0 0 8px; }
  .sub { color: #bdbdbd; margin-bottom: 26px; }
  .clock { font: 104px/1 "JetBrainsMono Nerd Font Mono", monospace; letter-spacing: 2px; margin: 6px 0 14px; }
  .track { height: 4px; background: #2a2a2a; margin-bottom: 26px; }
  .track i { display: block; height: 4px; width: 0; background: #fff; }
  .tip { color: #d0d0d0; font-size: 17px; margin-bottom: 26px; }
  .row { display: flex; align-items: center; height: 50px; padding: 0 14px; border-radius: 4px; color: #d0d0d0; font-size: 17px; cursor: default; }
  .row .icon { width: 34px; font-size: 20px; }
  .row .label { flex: 1; }
  .row .hint { color: #7a7a7a; font-size: 14px; }
  .row.selected { background: #fff; color: #000; }
  .row.selected .hint { color: #3a3a3a; }
]]

local BIG_SCRIPT = [[
  const rows = Array.from(document.querySelectorAll(".row"));
  let selected = Math.max(0, Number(document.body.dataset.selected || 1) - 1);
  const send = (type, id) => window.webkit.messageHandlers.omv.postMessage({ type, id: id || "" });
  const draw = () => rows.forEach((row, index) => row.classList.toggle("selected", index === selected));
  document.addEventListener("keydown", (event) => {
    if (event.key === "ArrowDown") selected = (selected + 1) % rows.length;
    else if (event.key === "ArrowUp") selected = (selected - 1 + rows.length) % rows.length;
    else if (event.key === "Enter") return send("choose", rows[selected].dataset.id);
    else {
      const keyed = rows.find((row) => row.dataset.key === event.key.toLowerCase());
      if (keyed) return send("choose", keyed.dataset.id);
      return;
    }
    event.preventDefault();
    draw();
  });
  rows.forEach((row) => row.addEventListener("click", () => send("choose", row.dataset.id)));
  const clock = document.querySelector(".clock");
  if (clock) {
    const ends = Number(clock.dataset.ends), seconds = Number(clock.dataset.seconds);
    const bar = document.querySelector(".track i");
    const tick = () => {
      const left = Math.max(0, Math.round(ends - Date.now() / 1000));
      clock.textContent = Math.floor(left / 60) + ":" + String(left % 60).padStart(2, "0");
      bar.style.width = (100 * (1 - left / seconds)) + "%";
    };
    tick();
    setInterval(tick, 250);
  }
  draw();
]]

local function bigRow(row)
  local key = row.key and (' data-key="' .. card.escape(row.key) .. '"') or ""
  return '<div class="row" data-id="' .. card.escape(row.id) .. '"' .. key .. ">"
    .. "<span class=icon>" .. card.escape(row.icon or "") .. "</span>"
    .. "<span class=label>" .. card.escape(row.label) .. "</span>"
    .. "<span class=hint>" .. card.escape(row.hint or "") .. "</span></div>"
end

local function dotsHtml(dots)
  if not dots then return "" end
  local parts = {}
  for index = 1, dots.total do parts[index] = index <= dots.filled and "<b class=on></b>" or "<b></b>" end
  return "<div class=dots>" .. table.concat(parts) .. "</div>"
end

-- screen = { kicker, dots = { filled, total }, title, sub, countdown = { ends, seconds }, tip, rows, selected }
function card.big(screen)
  local rows = {}
  for _, row in ipairs(screen.rows) do rows[#rows + 1] = bigRow(row) end
  local body = "<div class=kicker>" .. card.escape(screen.kicker) .. "</div>" .. dotsHtml(screen.dots)
  if screen.title then body = body .. "<div class=title>" .. card.escape(screen.title) .. "</div>" end
  if screen.sub then body = body .. "<div class=sub>" .. card.escape(screen.sub) .. "</div>" end
  if screen.countdown then
    body = body .. '<div class=clock data-ends="' .. screen.countdown.ends .. '" data-seconds="' .. screen.countdown.seconds .. '"></div>'
      .. "<div class=track><i></i></div>"
  end
  if screen.tip then body = body .. "<div class=tip>󰾄&nbsp; " .. card.escape(screen.tip) .. "</div>" end
  return "<!doctype html><meta charset=utf-8><style>" .. BIG_STYLE .. "</style>"
    .. '<body class="big" data-selected="' .. (screen.selected or 1) .. '"><div class=card>'
    .. body .. table.concat(rows) .. "</div><script>" .. BIG_SCRIPT .. "</script></body>"
end

return card
