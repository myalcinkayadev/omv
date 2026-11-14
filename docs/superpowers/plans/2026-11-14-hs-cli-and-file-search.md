# hs command and palette file search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hammerspoon installs the `hs` command itself; with `file-search=on` in `~/.config/omv/flags`, the palette lists recent files matching what's typed.

**Architecture:** Pure Lua modules (`hscli.lua`, `flags.lua`, `files.lua`) hold the rules and are tested with luajit; `init.lua` and `features/windows.lua` wire them to Hammerspoon. The card page asks for files with a `files` message and receives rows through `omvFiles(query, html)`.

**Tech Stack:** Hammerspoon Lua, luajit tests (`tests/check.lua`), bash doctor tests, Python contract tests.

**Spec:** `docs/superpowers/specs/2026-11-14-hs-cli-and-file-search-design.md`

## Global Constraints

- New top-level files in `hammerspoon/.hammerspoon/` need `stow --dir=. --target=$HOME --restow hammerspoon` before reload, or `init.lua` fails and every key goes.
- Flag file: `~/.config/omv/flags`; flag name `file-search`; default off.
- Search: 3+ characters, 300ms pause, `mdfind -onlyin $HOME`, names containing the text (`cd`), opened or modified in the last 30 days, drop `/Library/`, `/node_modules/`, `/.git/`, at most 20, heading "Files".
- Never block Hammerspoon (`hs.task`, no `hs.execute`, no `waitUntilExit`). Typed text never goes through a shell.
- Test names: "should <behavior> when <condition>".

## Review Focus

1. Flag off: the page sends no `files` message and no `mdfind` runs, whatever is typed.
2. Typing fast: only the latest text's answer shows; an answer for older text is dropped, and a running `mdfind` is stopped when a newer one starts.
3. Text with `"`, `\`, `*` or a quote-heavy name: no broken query, no error in the console.
4. Palette closed while a search runs: the answer arrives to no page and nothing errors.
5. A file name containing `<`, `&` or `"`: shown as text, not markup.

---

### Task 1: Install the hs command

**Files:**
- Create: `hammerspoon/.hammerspoon/hscli.lua`
- Modify: `hammerspoon/.hammerspoon/init.lua` (after `require("hs.ipc")`), `doctor.sh` (missing-hs fix text), `README.md` (Install)
- Test: `tests/hscli_test.lua`, `tests/hscli_test.sh`, `tests/doctor_test.sh`, `tests/config_contract_test.py`

**Interfaces:**
- Produces: `hscli.prefix(homebrewExists: boolean) -> string`.

- [ ] **Step 1: Failing tests:**
  - `hscli_test.lua`: should install into /opt/homebrew when Homebrew lives there → `hscli.prefix(true) == "/opt/homebrew"`; should install into /usr/local when it doesn't → `hscli.prefix(false) == "/usr/local"`.
  - `config_contract_test.py`: `test_should_install_the_hs_command_after_loading_ipc` → in `init.lua`, `require("hs.ipc")` appears before `cliInstall`.
  - `doctor_test.sh`: change `reports_missing_hs` to expect `✗ the hs command isn't installed — fix: reload Hammerspoon`.
- [ ] **Step 2: Run** `bash tests/hscli_test.sh; bash tests/doctor_test.sh; python3 -I tests/config_contract_test.py` — expect the new ones FAIL.
- [ ] **Step 3: Implement** `hscli.prefix`; in `init.lua`: `local prefix = require("hscli").prefix(hs.fs.attributes("/opt/homebrew") ~= nil)`, then `if not hs.ipc.cliStatus(prefix, true) then hs.ipc.cliInstall(prefix, true) end`; doctor fix text; README line.
- [ ] **Step 4: Run** the same commands — expect all `ok`.
- [ ] **Step 5: Restow, reload, check by hand:** `ls -l /opt/homebrew/bin/hs` unchanged; `hs -c 'return 1'` answers.
- [ ] **Step 6: Commit** `feat: install the hs command from Hammerspoon`

### Task 2: Feature flags

**Files:**
- Create: `hammerspoon/.hammerspoon/flags.lua`
- Test: `tests/flags_test.lua`, `tests/flags_test.sh`

**Interfaces:**
- Produces: `flags.DEFAULTS = { ["file-search"] = false }`; `flags.PATH = os.getenv("HOME") .. "/.config/omv/flags"`; `flags.read(text: string|nil) -> { [name] = boolean }` (defaults merged with the file's lines).

- [ ] **Step 1: Failing tests** (`flags.read(...)["file-search"]`):
  - should be off when there's no flags file → `read(nil)` false
  - should turn a flag on when its line says on → `read("file-search=on\n")` true
  - should turn a flag off when its line says off → `read("file-search=off")` false
  - should ignore spaces around the name and value → `read("  file-search = on ")` true
  - should ignore a comment line → `read("# file-search=on")` false
  - should ignore a value that isn't on or off → `read("file-search=yes")` false
  - should ignore an unknown flag → `read("nope=on")["nope"] == nil`
  - should let the last line win → `read("file-search=on\nfile-search=off")` false
- [ ] **Step 2: Run** `bash tests/flags_test.sh` — expect FAIL (module missing).
- [ ] **Step 3: Implement** `flags.read`.
- [ ] **Step 4: Run** — expect all `ok`.
- [ ] **Step 5: Commit** `feat: read feature flags from ~/.config/omv/flags`

### Task 3: The search's rules

**Files:**
- Create: `hammerspoon/.hammerspoon/files.lua`
- Modify: `hammerspoon/.hammerspoon/palette.lua` (`palette.parse`)
- Test: `tests/files_test.lua`, `tests/files_test.sh`, `tests/palette_test.lua`

**Interfaces:**
- Produces:
  - `files.MIN_LENGTH = 3`, `files.LIMIT = 20`, `files.DAYS = 30`.
  - `files.arguments(text: string, home: string) -> string[] | nil`: `mdfind` arguments, or nil when the cleaned text is shorter than 3.
  - `files.rows(output: string, home: string) -> row[]`: `{ id = "file:<path>", icon = "󰈔", label = <name>, hint = "~/<folder>", group = "Files" }`.
  - `palette.parse("file:/x/y.md") -> "file", "/x/y.md"`.
- [ ] **Step 1: Failing tests:**
  - should search names containing the text → `arguments("readme", "/Users/me")` = `{ "-onlyin", "/Users/me", '(kMDItemFSName == "*readme*"cd) && ((kMDItemLastUsedDate >= $time.today(-30)) || (kMDItemFSContentChangeDate >= $time.today(-30)))' }`
  - should ask nothing for fewer than 3 characters → `arguments("re", h) == nil`
  - should drop quotes, backslashes and stars from the text → `arguments('re"a\\d*me', h)[3]` contains `*readme*`
  - should ask nothing when only stars and quotes were typed → `arguments('"**"', h) == nil`
  - should list a file by its name → `rows("/Users/me/w/omv/README.md\n", "/Users/me")[1].label == "README.md"`
  - should hint its folder from home → `.hint == "~/w/omv"`
  - should open a file by its path → `.id == "file:/Users/me/w/omv/README.md"`
  - should leave out Library, node_modules and .git → three such lines → `#rows == 0`
  - should list at most 20 → 25 lines → `#rows == 20`
  - should skip blank lines → `"\n\n"` → `#rows == 0`
  - should read a file row → `palette.parse("file:/a b/c.md")` gives `"file", "/a b/c.md"`
- [ ] **Step 2: Run** `bash tests/files_test.sh; bash tests/palette_test.sh` — expect FAIL.
- [ ] **Step 3: Implement** `files.arguments`, `files.rows`, and `file` in `palette.parse`.
- [ ] **Step 4: Run** — expect all `ok`.
- [ ] **Step 5: Commit** `feat: decide which files the palette finds`

### Task 4: Files in the palette

**Files:**
- Modify: `hammerspoon/.hammerspoon/card.lua` (`card.html` with `screen.files`; the page script), `hammerspoon/.hammerspoon/features/windows.lua`, `README.md` (Palette)
- Test: `tests/palette_test.lua`

**Interfaces:**
- Consumes: Task 2's `flags.read`/`flags.PATH`; Task 3's `files.arguments`, `files.rows`, `palette.parse`.
- Produces: `screen.files` (bool) for `card.html`; page message `{ type = "files", id = <typed text> }`; page function `omvFiles(text, html)`; `card.filesCall(text: string, rows: row[]) -> string` (the JavaScript that hands rows to the page).

- [ ] **Step 1: Failing tests** (`palette_test.lua`):
  - should let a card ask for files when it allows them → `card.html({ prompt = "x", rows = {}, files = true })` contains `data-files`
  - should keep other cards from asking for files → without `files`, no `data-files`
  - should hand the page rows for the text they were found for → `card.filesCall("rea", rows)` starts with `omvFiles("rea",`
  - should escape a file name in the rows it hands over → a row labelled `a<b&"c.md` → the call contains `a&lt;b&amp;&quot;c.md` and no `a<b`
- [ ] **Step 2: Run** `bash tests/palette_test.sh` — expect the four FAIL.
- [ ] **Step 3: Implement:**
  - `card.html`: with `screen.files`, `data-files` on `body` and an empty `<div class=files></div>` after the rows.
  - Page script: `rows` becomes refreshable. While `data-files` is set, each change of the typed text clears the Files rows and, after 300ms without typing and with 3+ characters, sends `files` with the text. `omvFiles(text, html)` ignores an answer whose text isn't the one typed now, fills `.files`, re-reads the rows (hover and click work on new ones) and redraws, keeping the selection on the same row when it's still there.
  - `card.filesCall` builds the call with `card.jsString` and the row markup `card.html` uses.
  - `features/windows.lua`: reads the flags once at load (`flags.read(shell.readText(flags.PATH))`); the palette screen gets `files = flags["file-search"]`. On `files`: stop the running search task, start `mdfind` with `files.arguments`; on exit, if the palette is still open, `shell.view():evaluateJavaScript(card.filesCall(text, files.rows(output, shell.HOME)))`. On `choose` of a `file`: close and `open` the path.
  - README Palette: the flag, what's searched, how to turn it on.
- [ ] **Step 4: Run** `bash tests/run.sh` — expect exit 0.
- [ ] **Step 5: Restow, reload and check by hand:**
  - Flag absent: type `readme` → no Files heading; `pgrep mdfind` stays empty.
  - `echo file-search=on > ~/.config/omv/flags`, reload: type `readme` → Files with `README.md` (`~/workspace/omv`) after the other rows; Enter opens it.
  - Type `rea`, then quickly `dme`: only `readme`'s files show.
  - Close the palette mid-search: no console error.
  - Remove the flags file again and reload, so the Mac is as before unless the user keeps it on.
- [ ] **Step 6: Commit** `feat: find recent files in the palette`
