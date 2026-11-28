-- Right Command's commands: open, go to, move this to, close and quit, and what release does.
-- Run through voicecommands_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local voicecommands = require("voicecommands")

local context = {
  items = {
    { id = "window:11", label = "Zed — notes.md", group = "Windows" },
    { id = "window:12", label = "Ghostty — zsh", group = "Windows" },
    { id = "app:/Applications/Zed.app", label = "Zed", group = "Apps" },
    { id = "app:/Applications/Zoom.app", label = "Zoom", group = "Apps" },
    { id = "app:/Applications/TextEdit.app", label = "TextEdit", group = "Apps" },
    { id = "command:4", label = "Open Zed", group = "Commands" },
    { id = "command:9", label = "Night light", group = "Commands" },
    { id = "app:/Applications/Slack.app", label = "Slack", group = "Apps" },
    { id = "app:/Applications/Slick.app", label = "Slick", group = "Apps" },
  },
  workspaces = { { number = "1", name = "Code" }, { number = "2", name = "Web" }, { number = "3" } },
  running = { "Zed", "TextEdit", "Ghostty" },
  focused = { id = "12", label = "Ghostty — zsh" },
}
local function target(text) return voicecommands.target(text, context) end

-- parse
local function verb(text) local said = voicecommands.parse(text) return said and said.verb end
check.that("should read open with its words", verb("Open Zed.") == "open" and table.concat(voicecommands.parse("Open Zed.").words, " ") == "Zed.")
check.that("should read go to and switch to as go", verb("go to three") == "go" and verb("Switch to code") == "go")
check.that("should read move this to as move", verb("move this to two") == "move" and verb("move to web") == "move")
check.that("should read close and quit", verb("close this") == "close" and verb("Quit TextEdit") == "quit")
check.that("should give nil for anything else", verb("make coffee") == nil and verb("") == nil)

-- target
check.that("should run Zed when open said is heard", (function()
  local t = target("open said")
  return t.kind == "run" and t.item.id == "app:/Applications/Zed.app"
end)())
check.that("should run Zed the app when open zed is heard", target("Open Zed.").item.id == "app:/Applications/Zed.app")
check.that("should run a command by its name", target("open night light").item.id == "command:9")
check.that("should give workspace 3 when go to three is said", (function()
  local t = target("go to three")
  return t.kind == "workspace" and t.workspace.number == "3"
end)())
check.that("should give the workspace named Code when go to code is said", target("go to code").workspace.number == "1")
check.that("should give move to 2 when move this to two is said", (function()
  local t = target("move this to two")
  return t.kind == "move" and t.workspace.number == "2"
end)())
check.that("should give confirm quit when quit zed is said", (function()
  local t = target("quit zed")
  return t.kind == "confirm" and t.action == "quit" and t.name == "Zed"
end)())
check.that("should give confirm close for the focused window when close this is said", (function()
  local t = target("close this")
  return t.kind == "confirm" and t.action == "close" and t.id == "12"
end)())
check.that("should give choose with up to 5 when two rows tie", (function()
  local t = target("open slock")
  return t.kind == "choose" and #t.candidates == 2 and #t.candidates <= 5
end)())
check.that("should give none when nothing sounds like it", target("open banana").kind == "none")
check.that("should give none when no verb is heard", target("make coffee").kind == "none")

-- resultLine
check.that("should name each kind for the pill", voicecommands.resultLine(target("open said")) == "→ Zed · app"
  and voicecommands.resultLine(target("go to code")) == "→ workspace 1 · Code"
  and voicecommands.resultLine(target("move this to two")) == "→ move this to 2 · Web"
  and voicecommands.resultLine(target("quit zed")) == "Quit Zed · press Enter after release")

-- decide: agents first, then commands.
local sessions = { { id = "/dev/ttys001", label = "omv", state = "done", hint = "done · 2 min" } }
check.that("should decide for an agent when tell is said", (function()
  local t = voicecommands.decide("tell omv run it", sessions, nil, context)
  return t.source == "agent" and t.kind == "paste" and t.chip == "omv"
end)())
check.that("should decide for a command when open is said", (function()
  local t = voicecommands.decide("open said", sessions, nil, context)
  return t.source == "command" and t.kind == "run" and t.chip == "Zed" and t.line == "→ Zed · app"
end)())
check.that("should give a hint naming both kinds when no verb is heard", (function()
  local t = voicecommands.decide("make coffee", sessions, nil, context)
  return t.kind == "none" and t.line:find("open", 1, true) ~= nil and t.line:find("tell", 1, true) ~= nil
end)())
check.that("should decide for an agent only when there's no command context", voicecommands.decide("open said", sessions, nil, nil).kind == "none")
check.that("should mark a run go and a quit warn", voicecommands.decide("open said", sessions, nil, context).tone == "go"
  and voicecommands.decide("quit zed", sessions, nil, context).tone == "warn")

check.finish()
