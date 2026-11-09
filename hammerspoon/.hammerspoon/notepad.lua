-- The quick note editor: a card that grows as you type, with Markdown marks shown dimmed.
-- Enter carries a list on, Tab indents it, Cmd+Enter saves. Escape is a hotkey, so init.lua
-- decides what it does and calls arm() here when the note has text.
-- Reaches init.lua through the "omv" message handler as { type, id }:
--   draft (every edit, id = the text), resize (id = the height the card needs),
--   submit (id = the text) and discard.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = require("card")

local notepad = {}

local STYLE = [[
  html, body { height: auto; }
  body { display: block; padding: 14px; }
  .editor { position: relative; font-size: 17px; line-height: 1.6; padding: 6px 10px 0; }
  .editor pre, .editor textarea { margin: 0; padding: 0; border: 0; font: inherit; line-height: inherit;
    white-space: pre-wrap; overflow-wrap: break-word; width: 100%; }
  .editor pre { position: absolute; top: 6px; left: 10px; right: 10px; width: auto; pointer-events: none; overflow: hidden; }
  .editor textarea { position: relative; display: block; background: transparent; color: transparent;
    caret-color: #fff; caret-shape: block; resize: none; outline: none; overflow-y: auto; scrollbar-width: none; }
  .editor textarea::-webkit-scrollbar { display: none; }
  .editor textarea::placeholder { color: #fff; opacity: 1; }
  .mk { color: #5a5a5a; }
  .hd, .b { font-weight: 700; }
  .done { color: #7a7a7a; text-decoration: line-through; }
  .q { color: #bdbdbd; }
  .code { color: #d0d0d0; background: #1a1a1a; }
  .foot { color: #7a7a7a; padding: 22px 10px 8px; display: flex; gap: 22px; white-space: nowrap; }
  .foot.armed { color: #fff; }
  kbd { font: inherit; border: 1px solid #3a3a3a; padding: 0 5px; }
  .foot.armed kbd { background: #fff; color: #000; border-color: #fff; }
]]

local SCRIPT = [[
  const ta = document.querySelector("textarea");
  const hl = document.querySelector("pre");
  const foot = document.querySelector(".foot");
  const LIST = /^(\s*)(- \[[ xX]\] |[-*] |\d+\. )/;
  let armed = false;

  const send = (type, id) => window.webkit.messageHandlers.omv.postMessage({ type, id: id || "" });
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const mark = (m) => '<span class="mk">' + m + "</span>";

  function inline(s) {
    return s
      .replace(/(\*\*)(.+?)(\*\*)/g, (_, a, b, c) => mark(a) + '<span class="b">' + b + "</span>" + mark(c))
      .replace(/(`)([^`]+)(`)/g, (_, a, b, c) => mark(a) + '<span class="code">' + b + "</span>" + mark(c));
  }

  function line(raw) {
    const s = esc(raw);
    let m;
    if ((m = s.match(/^(#{1,6} )(.*)$/))) return mark(m[1]) + '<span class="hd">' + inline(m[2]) + "</span>";
    if ((m = s.match(/^(&gt; )(.*)$/))) return mark(m[1]) + '<span class="q">' + inline(m[2]) + "</span>";
    if ((m = s.match(/^(\s*- \[[xX]\] )(.*)$/))) return mark(m[1]) + '<span class="done">' + m[2] + "</span>";
    if ((m = s.match(/^(\s*(?:- \[ \] |[-*] |\d+\. ))(.*)$/))) return mark(m[1]) + inline(m[2]);
    return inline(s);
  }

  function drawFoot() {
    foot.classList.toggle("armed", armed);
    if (armed) foot.innerHTML = "<span><kbd>esc</kbd> keep draft</span><span><kbd>⌘↵</kbd> save</span><span><kbd>⌘⌫</kbd> discard</span>";
    else if (/^# \S/.test(ta.value)) foot.innerHTML = "<span>New page in Inbox, linked from today</span>";
    else if (ta.value) foot.innerHTML = "<span>⌘↵ save</span><span>esc close</span>";
    else foot.innerHTML = "<span>Adds to today's daily note</span>";
  }

  // The card grows with the text up to half the screen, then the text scrolls.
  function fit() {
    ta.style.height = "auto";
    const chrome = document.body.offsetHeight - document.querySelector(".editor").offsetHeight + 6;
    const limit = screen.availHeight / 2 - chrome;
    ta.style.height = Math.min(ta.scrollHeight, limit) + "px";
    hl.style.height = ta.style.height;
    hl.scrollTop = ta.scrollTop;
    send("resize", String(Math.ceil(document.body.offsetHeight)));
  }

  function draw() {
    hl.innerHTML = ta.value.split("\n").map(line).join("\n") + "\n";
    drawFoot();
    fit();
  }

  function currentLine() {
    const start = ta.value.lastIndexOf("\n", ta.selectionStart - 1) + 1;
    let end = ta.value.indexOf("\n", ta.selectionStart);
    if (end === -1) end = ta.value.length;
    return { start, end, text: ta.value.slice(start, end) };
  }

  function edit(start, end, text, caret) {
    ta.setRangeText(text, start, end, "end");
    if (caret !== undefined) ta.selectionStart = ta.selectionEnd = caret;
    changed();
  }

  // Enter on a list item starts the next one; on an empty item it ends the list.
  function carryList(event) {
    const cur = currentLine();
    const m = cur.text.match(LIST);
    if (!m) return;
    event.preventDefault();
    if (cur.text.slice(m[0].length).trim() === "") return edit(cur.start, cur.end, "", cur.start);
    let prefix = m[0].replace(/\[[xX]\]/, "[ ]");
    const num = prefix.match(/^(\s*)(\d+)\. $/);
    if (num) prefix = num[1] + (Number(num[2]) + 1) + ". ";
    edit(ta.selectionStart, ta.selectionEnd, "\n" + prefix);
  }

  function indent(event) {
    const cur = currentLine();
    if (!LIST.test(cur.text)) return;
    event.preventDefault();
    const pos = ta.selectionStart;
    if (!event.shiftKey) return edit(cur.start, cur.start, "  ", pos + 2);
    if (cur.text.startsWith("  ")) edit(cur.start, cur.start + 2, "", pos - 2);
  }

  function changed() {
    armed = false;
    draw();
    send("draft", ta.value);
  }

  // Called by init.lua on the first Escape when there is text to lose.
  window.arm = () => { armed = true; drawFoot(); };

  ta.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && event.metaKey) { event.preventDefault(); return send("submit", ta.value); }
    if (event.key === "Backspace" && event.metaKey && armed) { event.preventDefault(); return send("discard"); }
    if (event.key === "Enter" && !event.shiftKey) return carryList(event);
    if (event.key === "Tab") return indent(event);
  });
  ta.addEventListener("input", changed);
  ta.addEventListener("scroll", () => { hl.scrollTop = ta.scrollTop; });

  ta.focus();
  ta.selectionStart = ta.selectionEnd = ta.value.length;
  draw();
]]

-- draft is the text kept from the last time the card closed unsaved.
function notepad.html(draft)
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. STYLE .. "</style><body>"
    .. '<div class=editor><pre aria-hidden=true></pre><textarea rows=1 placeholder="Note…" spellcheck=false>'
    -- A newline right after <textarea> is dropped by the parser, so a draft that starts with one keeps it.
    .. "\n" .. card.escape(draft or "") .. "</textarea></div>"
    .. "<div class=foot></div>"
    .. "<script>" .. SCRIPT .. "</script></body>"
end

return notepad
