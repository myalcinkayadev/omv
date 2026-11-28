-- Renders the Omarchy-style card shared by the system menu and the key list: a search
-- prompt on top, then rows to pick from. Typing filters the rows. Up and Down move,
-- Enter or Right picks, Left or Backspace on an empty search goes back, Escape closes.
-- In a card with columns, Left and Right move between columns instead, so only Enter picks.
-- Picks reach init.lua through the "omv" message handler as { type, id }.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = {}

-- A page's script, read from beside this file; empty when the file is missing.
function card.readBeside(name)
  local folder = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
  local file = io.open(folder .. name, "r")
  if not file then return "" end
  local text = file:read("*a")
  file:close()
  return text
end

-- The palette's calculator. Empty when calc.js is missing: the palette then filters as
-- before, with no calculator row.
local CALC = card.readBeside("calc.js")
-- The palette's clipboard actions, read the same way; empty leaves them out.
local TRANSFORM = card.readBeside("transform.js")

card.STYLE = [[
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; background: #000; color: #fff; overflow: hidden;
    font: 15px "JetBrainsMono Nerd Font Propo", "JetBrainsMono Nerd Font Mono", monospace; }
  body { border: 2px solid #8d8d8d; padding: 14px; display: flex; flex-direction: column; }
  .prompt { font-size: 17px; padding: 6px 10px 12px; white-space: pre; }
  .prompt.empty::before { content: attr(data-prompt); }
  /* File search's sign, at the prompt's right while Spotlight is asked. */
  .busy { float: right; font-size: 13px; color: #7a7a7a; margin-top: 3px; visibility: hidden; }
  .busy.on { visibility: visible; }
  .caret { display: inline-block; width: 8px; height: 18px; background: #fff; vertical-align: -3px; margin-left: 1px; }
  .rows { overflow-y: auto; flex: 1; scrollbar-width: none; }
  .rows::-webkit-scrollbar { display: none; }
  .row { display: flex; align-items: center; height: 44px; padding: 0 12px; border-radius: 4px; color: #d0d0d0; cursor: default; }
  .row .icon { width: 28px; font-size: 18px; }
  .thumb { width: 20px; height: 20px; object-fit: cover; vertical-align: middle; border: 1px solid #2a2a2a; }
  .row .label { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .row .hint { color: #9a9a9a; padding-left: 16px; white-space: nowrap; }
  .row.sounds .label::after { content: "  sounds like"; color: #8d8d8d; font-size: 11px; }
  .row.selected { background: #fff; color: #000; }
  .row.selected .hint { color: #3a3a3a; }
  .row.hidden { display: none; }
  .note { display: flex; align-items: center; height: 44px; padding: 0 12px; color: #7a7a7a; }
  .note .icon { width: 28px; font-size: 18px; }
  .note .label { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .quote { padding: 0 12px 4px; font-size: 13px; line-height: 20px; color: #a6a6a6; white-space: pre-wrap; overflow-wrap: anywhere; max-height: 60px; overflow: hidden; }
  .passage { padding: 2px 12px 10px; font-size: 15px; line-height: 22px; white-space: pre-wrap; overflow-wrap: anywhere; max-height: 220px; overflow-y: auto; -webkit-user-select: text; }
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
  /* The palette's clipboard rows: a short tag naming the kind, in the icon's place. Green and
     red aren't grays, so a theme leaves them as they are. */
  .row .icon.tag { flex: none; width: 40px; margin-right: 10px; font-size: 10px; letter-spacing: 0.5px; line-height: 16px;
    text-align: center; border: 1px solid #2a2a2a; border-radius: 4px; color: #8d8d8d; }
  .row.selected .icon.tag { border-color: #bbbbbb; color: #333333; }
  .row .icon.tag.bad { color: #e88b7f; border-color: #e88b7f; }
  .row .hint.tone-ok { color: #7fd1ae; }
  .row .hint.tone-bad { color: #e88b7f; }
  .row.selected .hint.tone-ok { color: #1d7a52; }
  .row.selected .hint.tone-bad { color: #a33a2c; }
  .foot[hidden] { display: none; }
  /* The palette's clipboard footer shows and hides with its row, so it reaches the card's edge itself. */
  .foot.clipfoot { margin-bottom: -14px; }
  /* The away digest: a count line under the title, a status at its right, a key footer, and
     icons in a tone. Yellow and green aren't grays, so a theme leaves them as they are. */
  .status { float: right; font-size: 13px; margin-top: 3px; }
  .status.ask { color: #f2c94c; }
  .status.ok { color: #7fd1ae; }
  .sub { padding: 0 10px 8px; margin-top: -6px; color: #7a7a7a; font-size: 13px; }
  .row.tone-ask .icon { color: #f2c94c; }
  .row.selected.tone-ask .icon { color: #9a6a00; }
  .row.tone-ok .icon { color: #7fd1ae; }
  .row.tone-muted .icon { color: #7a7a7a; }
  body.compact .row.tone-muted .label, .row.tone-muted .label { color: #7a7a7a; }
  body.compact .row.selected.tone-muted .label { color: #000; }
  /* A card with a footer ends with it, so the body's bottom padding goes. */
  body.footed { padding-bottom: 0; }
  .foot { display: flex; flex-wrap: wrap; gap: 6px 18px; align-items: center; border-top: 1px solid #2a2a2a;
    margin: 8px -14px 0; padding: 10px 24px 12px; color: #7a7a7a; font-size: 12px; }
  .foot kbd { font: inherit; color: #fff; border: 1px solid #2a2a2a; border-radius: 4px; padding: 0 6px; margin-right: 6px; }
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
  let query = document.body.dataset.query || "";
  // An input card has no rows to pick: Enter sends what was typed.
  const takesInput = document.body.dataset.input !== undefined;
  let selected = Math.max(0, Number(document.body.dataset.selected || 1) - 1);

  const send = (type, id) => window.webkit.messageHandlers.omv.postMessage({ type, id: id || "" });
  const visible = () => rows.filter((row) => !row.classList.contains("hidden"));
  // The clipboard rows, first in the list: what the clipboard holds, or a typed action word's
  // result. The footer naming their keys shows only while one of them is selected.
  const clipRows = typeof omvTransform === "function" ? Array.from(document.querySelectorAll(".row.clip")) : [];
  const clipFoot = document.querySelector(".foot.clipfoot");
  // The calculator row, first in the list: shown while the search is a whole sum.
  const calc = typeof omvCalc === "function" ? document.querySelector(".row.calc") : null;
  // File search, on in a card with data-files: after a pause in typing, Hammerspoon is asked
  // for files matching the text, and its answer fills .files through omvFiles.
  const files = document.body.dataset.files !== undefined ? document.querySelector(".files") : null;
  const FILES_PAUSE_MS = 300, FILES_MIN_LENGTH = 3;
  const busy = document.querySelector(".busy");
  let filesTimer = null;
  // Files are on their way for the typed text: "No matches" waits for them, so it never
  // shows while a search may still find something.
  let filesPending = false;
  // Sound matches, in a card with data-sounds: after a pause in typing, Hammerspoon is asked
  // for the rows the text finds only by how it sounds, such as Zed for "said"; omvSounds shows
  // them, marked "sounds like". Substring matches keep their place.
  const sounds = document.body.dataset.sounds !== undefined;
  const SOUNDS_PAUSE_MS = 150, SOUNDS_MIN_LENGTH = 3;
  let soundIds = new Set(), soundsTimer = null;

  // Browser tabs, in a card with a .tabs place among its rows: asked for once the page has
  // loaded, so the answer always finds omvTabs, and put there when they arrive.
  const tabs = document.querySelector(".tabs");

  // Currency rates, from Hammerspoon when the page asks; the calculator redraws with them.
  let rates = null, ratesAsked = false;
  window.omvSetRates = (given) => { rates = given; draw(); };

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
      // Spotlight already matched file rows to the typed text, ignoring accents, and they're
      // cleared whenever the text changes, so filtering them again would only hide matches.
      if (row === calc || row.classList.contains("clip") || (files && files.contains(row))) return;
      const haystack = ((row.dataset.group || "") + " " + (row.dataset.keywords || "") + " " + row.textContent).toLowerCase();
      const found = words.every((word) => haystack.includes(word));
      const soundsLike = !found && soundIds.has(row.dataset.id);
      row.classList.toggle("hidden", !found && !soundsLike);
      row.classList.toggle("sounds", soundsLike);
    });
    if (calc) {
      // A sum first, then a conversion; a currency one asks Hammerspoon for rates, once.
      let result = omvCalc(query), note = null;
      if (result === null && typeof omvConvert === "function") {
        if (!ratesAsked && omvConvert.wantsRates(query)) { ratesAsked = true; send("rates"); }
        const converted = omvConvert(query, { now: Date.now(), rates: rates });
        if (converted) { result = converted.value; note = converted.note; }
      }
      calc.classList.toggle("hidden", result === null);
      calc.dataset.id = "calc:" + (result || "");
      calc.querySelector(".label").textContent = "= " + (result || "");
      calc.querySelector(".hint").textContent = (note ? note + " · " : "") + "Enter copies";
    }
    if (clipRows.length) {
      const found = omvTransform(query, window.omvClip, Date.now());
      clipRows.forEach((row, index) => {
        const item = found[index];
        row.classList.toggle("hidden", !item);
        if (!item) return;
        row.dataset.id = item.verb ? "verb:" + item.verb : item.value === null ? "none:" : "clip:" + item.value;
        const tag = row.querySelector(".tag");
        tag.textContent = item.kind;
        tag.classList.toggle("bad", item.tone === "bad");
        row.querySelector(".label").textContent = item.label;
        const hint = row.querySelector(".hint");
        hint.textContent = item.hint || "";
        hint.className = "hint" + (item.tone ? " tone-" + item.tone : "");
      });
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
    none.style.display = (shown.length && !takesInput) || filesPending ? "none" : "block";
    if (clipFoot) clipFoot.hidden = !(shown[selected] && (shown[selected].dataset.id || "").startsWith("clip:"));
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
    if (!row) return;
    const id = row.dataset.id || "";
    // A half-typed action word completes to the whole one, applied to the clipboard.
    if (id.startsWith("verb:")) { query = id.slice(5); selected = 0; return draw(); }
    // An error row has nothing to copy.
    if (id === "none:") return;
    send("choose", id);
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

  // The sound matches for older text go at once; new ones are asked for after a pause.
  function askSounds() {
    if (!sounds) return;
    clearTimeout(soundsTimer);
    soundIds = new Set();
    if (query.replace(/[^\p{L}\p{N}]/gu, "").length < SOUNDS_MIN_LENGTH) return;
    const asked = query;
    soundsTimer = setTimeout(() => send("sounds", asked), SOUNDS_PAUSE_MS);
  }

  // Called from Hammerspoon with the ids of the rows text finds by sound; dropped when other
  // text is typed by then.
  window.omvSounds = (asked, ids) => {
    if (asked !== query) return;
    soundIds = new Set(ids);
    draw();
  };

  // The files found for older text go at once; new ones are asked for after a pause.
  function askFiles() {
    if (!files) return;
    clearTimeout(filesTimer);
    if (files.innerHTML !== "") { files.innerHTML = ""; collect(); }
    busy.classList.remove("on");
    // Letters as Lua counts them: no spaces, and none of the " \ * it drops.
    filesPending = Array.from(query.replace(/["\\*\s]/g, "")).length >= FILES_MIN_LENGTH;
    if (!filesPending) return;
    const asked = query;
    filesTimer = setTimeout(() => {
      busy.classList.add("on");
      send("files", asked);
    }, FILES_PAUSE_MS);
  }

  // Rows that arrive while the card is open go into place. The selected row stays selected
  // when it's still shown.
  function fill(place, html) {
    const was = visible()[selected];
    place.innerHTML = html;
    collect();
    place.querySelectorAll(".row").forEach(wire);
    draw();
    const at = visible().indexOf(was);
    if (at >= 0 && at !== selected) { selected = at; draw(); }
  }

  // Called from Hammerspoon with the rows found for text. An answer for text that's no longer
  // typed is dropped.
  window.omvFiles = (asked, html) => {
    if (!files || asked !== query) return;
    filesPending = false;
    busy.classList.remove("on");
    fill(files, html);
  };

  // Called from Hammerspoon with the browser's tabs, filtered by what's typed like any row.
  window.omvTabs = (html) => {
    if (tabs) fill(tabs, html);
  };

  document.addEventListener("keydown", (event) => {
    const shown = visible();
    const typed = query;
    if (event.key === "Escape") return send("close");
    // A row with data-key is picked by Cmd and its key, such as Cmd+C to copy.
    const keyed = event.metaKey && !files && rows.find((row) => row.dataset.key === event.key.toLowerCase());
    if (keyed) {
      event.preventDefault();
      return pick(keyed);
    }
    // File search's actions: Cmd+Enter shows the selected file in Finder, Cmd+C copies its
    // path. Hammerspoon ignores them on any other row.
    if (files && event.metaKey && (event.key === "Enter" || event.key.toLowerCase() === "c")) {
      event.preventDefault();
      if (shown[selected]) send(event.key === "Enter" ? "reveal" : "copy", shown[selected].dataset.id);
      return;
    }
    // A card that asks for Tab, such as the process card switching its sort, hears it.
    if (event.key === "Tab" && document.body.dataset.tab !== undefined) {
      event.preventDefault();
      return send("tab", shown[selected] ? shown[selected].dataset.id : "");
    }
    // A card in step mode, the display profile editor, steps the row's value with Left and Right,
    // sent as "1:layout" or "-1:layout".
    if ((event.key === "ArrowRight" || event.key === "ArrowLeft") && document.body.dataset.step !== undefined) {
      event.preventDefault();
      if (shown[selected]) send("step", (event.key === "ArrowRight" ? "1:" : "-1:") + shown[selected].dataset.id);
      return;
    }
    if (event.key === "ArrowDown" || (event.ctrlKey && event.key === "n")) selected = (selected + 1) % Math.max(1, shown.length);
    else if (event.key === "ArrowUp" || (event.ctrlKey && event.key === "p")) selected = (selected - 1 + shown.length) % Math.max(1, shown.length);
    else if (event.key === "Enter" && takesInput) return send("submit", query);
    // Shift+Enter on a clipboard row pastes its result where you were typing.
    else if (event.key === "Enter" && event.shiftKey && shown[selected] && (shown[selected].dataset.id || "").startsWith("clip:")) {
      event.preventDefault();
      return send("paste", shown[selected].dataset.id);
    }
    else if (inColumns && event.key === "ArrowRight") sideways(1);
    else if (inColumns && event.key === "ArrowLeft") sideways(-1);
    else if (event.key === "Enter" || event.key === "ArrowRight") return pick(shown[selected]);
    else if (event.key === "Backspace" && query === "" && document.body.dataset.clear !== undefined) { event.preventDefault(); if (shown[selected]) send("clear", shown[selected].dataset.id); return; }
    else if (event.key === "ArrowLeft" || (event.key === "Backspace" && query === "")) return send("back");
    else if (event.key === "Backspace") query = query.slice(0, -1);
    else if (event.key.length === 1 && !event.metaKey && !event.ctrlKey) { query += event.key; selected = 0; }
    else return;
    event.preventDefault();
    if (query !== typed) { askFiles(); askSounds(); }
    draw();
  });

  rows.forEach(wire);
  if (tabs) send("tabs");

  // The height the page needs, without the rows stretching to fill the window: Hammerspoon
  // sizes a card to fit it.
  window.omvContentHeight = () => {
    const root = document.documentElement.style, body = document.body.style, list = document.querySelector(".rows");
    const saved = [root.height, body.height, list ? list.style.flex : ""];
    root.height = "auto"; body.height = "auto"; if (list) list.style.flex = "none";
    const height = Math.ceil(document.body.getBoundingClientRect().height);
    root.height = saved[0]; body.height = saved[1]; if (list) list.style.flex = saved[2];
    return height;
  };

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

-- The tones a row's icon can take; any other value is left out of the page.
local TONES = { ask = true, ok = true, muted = true }

local function rowHtml(row)
  -- Where the palette puts the browser's tabs once they're read.
  if row.tabs then return "<div class=tabs></div>" end
  local icon = row.icon and ("<span class=icon>" .. card.escape(row.icon) .. "</span>") or ""
  -- A picture, such as a copied image's preview, takes the icon's place.
  if row.image then icon = '<span class=icon><img class=thumb src="' .. card.escape(row.image) .. '" alt=""></span>' end
  -- A note is only text: without the row class, keys, the pointer and Enter pass it by.
  if row.note then
    return "<div class=note>" .. icon .. "<span class=label>" .. card.escape(row.label) .. "</span></div>"
  end
  local hint = row.submenu and "›" or row.hint
  return '<div class="row' .. (TONES[row.tone] and (" tone-" .. row.tone) or "") .. '" data-id="' .. card.escape(row.id) .. '"'
    .. (row.group and (' data-group="' .. card.escape(row.group) .. '"') or "")
    .. (row.keywords and (' data-keywords="' .. card.escape(row.keywords) .. '"') or "")
    .. (row.submenu and " data-submenu" or "")
    .. (row.key and (' data-key="' .. card.escape(row.key) .. '"') or "") .. ">"
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

-- screen = { prompt = "System…", rows = { { id, icon, label, hint, submenu, group, note, key, tone } },
--            selected = 1, compact = false, columns = 1, input = false, hint = "", passage = "",
--            sub = { counts, status, tone }, footer = { { key, text } }, clearable = false,
--            clipActions = false, clip = nil, tab = false, step = false }
-- sub is a count line under the title with a status at its right; footer lists keys; a
-- clearable card sends clear and the selected row on Backspace. A row's tone, ask, ok or
-- muted, colours its icon. A card with clipActions, such as the palette, shows the clipboard
-- actions on top, for clip, the clipboard's text; Shift+Enter on one sends paste.
-- An input card sends what was typed on Enter, and shows its hint under the prompt; query is
-- text already typed in it, to change rather than retype. A
-- passage is text shown whole above the rows, wrapped, such as a translation; a quote, smaller
-- and grey above it, is what it came from. A row's key picks it with Cmd held.
-- A card with calc = true, such as the palette, works out a typed sum in its first row.
-- A card with tab sends tab and the selected row on Tab. A card with step, the display
-- profile editor, sends step on Left and Right instead of picking or going back.
local function subHtml(sub)
  if not sub then return "" end
  return "<div class=sub>" .. card.escape(sub.counts) .. "</div>"
end

local function statusHtml(sub)
  if not (sub and sub.status) then return "" end
  return '<span class="status ' .. (TONES[sub.tone] and sub.tone or "") .. '">' .. card.escape(sub.status) .. "</span>"
end

local function footerHtml(footer)
  if not footer then return "" end
  local keys = {}
  for _, entry in ipairs(footer) do
    keys[#keys + 1] = "<span>" .. (entry.key and ("<kbd>" .. card.escape(entry.key) .. "</kbd>") or "") .. card.escape(entry.text) .. "</span>"
  end
  return "<div class=foot>" .. table.concat(keys) .. "</div>"
end

-- Room for the most rows a half-typed action word can list.
local CLIP_ROWS = 3

function card.html(screen)
  local rows = rowsWithHeaders(screen.rows)
  local calc = screen.calc and CALC ~= ""
  if calc then
    table.insert(rows, 1, '<div class="row calc hidden" data-id="calc:"><span class=icon>󰃬</span>'
      .. "<span class=label></span><span class=hint>Enter copies</span></div>")
  end
  local clip = (screen.clipActions or screen.clip ~= nil) and TRANSFORM ~= ""
  if clip then
    for _ = 1, CLIP_ROWS do
      table.insert(rows, 1, '<div class="row clip hidden" data-group="Clipboard" data-id="none:"><span class="icon tag"></span>'
        .. "<span class=label></span><span class=hint></span></div>")
    end
    table.insert(rows, 1, '<div class=group data-name="Clipboard">Clipboard</div>')
  end
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. "</style>"
    .. '<body class="' .. (screen.compact and "compact" or "") .. (screen.footer and " footed" or "") .. '" data-selected="' .. (screen.selected or 1) .. '"'
    .. (screen.input and " data-input" or "") .. (screen.tab and " data-tab" or "") .. (screen.step and " data-step" or "") .. (calc and " data-calc" or "") .. (screen.files and " data-files" or "") .. (screen.sounds and " data-sounds" or "")
    .. (screen.clearable and " data-clear" or "") .. (screen.query and (' data-query="' .. card.escape(screen.query) .. '"') or "") .. ">"
    .. '<div class="prompt empty" data-prompt="' .. card.escape(screen.prompt) .. '"><span class=text></span>'
    .. "<span class=caret></span>"
    .. (screen.files and "<span class=busy>Searching files…</span>" or "") .. statusHtml(screen.sub) .. "</div>"
    .. subHtml(screen.sub)
    .. (screen.quote and ("<div class=quote>" .. card.escape(screen.quote) .. "</div>") or "")
    .. (screen.passage and ("<div class=passage>" .. card.escape(screen.passage) .. "</div>") or "")
    .. rowsOpen(screen.columns) .. table.concat(rows) .. (screen.files and "<div class=files></div>" or "") .. "<div class=none>" .. card.escape(screen.hint or "No matches") .. "</div></div>"
    .. footerHtml(screen.footer)
    .. (clip and ('<div class="foot clipfoot" hidden><span><kbd>Enter</kbd>copy</span><span><kbd>Shift+Enter</kbd>paste where you were typing</span>'
      .. "<span><kbd>Esc</kbd>close</span></div>") or "")
    .. (calc and ("<script>" .. CALC .. "</script>") or "")
    .. (clip and ("<script>window.omvClip = " .. (screen.clip and card.jsString(screen.clip) or "null") .. ";" .. TRANSFORM .. "</script>") or "")
    .. "<script>" .. SCRIPT .. "</script></body>"
end

-- The JavaScript that hands an open palette the ids of the rows text finds by sound.
function card.soundsCall(text, ids)
  local quoted = {}
  for index, id in ipairs(ids) do quoted[index] = card.jsString(id) end
  return "omvSounds(" .. card.jsString(text) .. ",[" .. table.concat(quoted, ",") .. "]);"
end

-- The JavaScript that hands an open palette the file rows found for text. The page drops
-- them when other text is typed by then. With none found, the card's one "No matches" says
-- so, once nothing else matches either.
function card.filesCall(text, fileRows)
  return "omvFiles(" .. card.jsString(text) .. "," .. card.jsString(table.concat(rowsWithHeaders(fileRows))) .. ");"
end

-- The JavaScript that hands an open palette the browser's tab rows.
function card.tabsCall(tabRows)
  return "omvTabs(" .. card.jsString(table.concat(rowsWithHeaders(tabRows))) .. ");"
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
