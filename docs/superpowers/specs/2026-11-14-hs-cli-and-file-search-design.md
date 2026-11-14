# Install the hs command, and file search in the palette behind a flag

Two changes, built in this order.

## 1. Install the hs command

**Why:** every bar click, the Bluetooth icon and the doctor talk to Hammerspoon through
`hs -c`. Nothing installs `hs`: on this Mac it's a link made by hand, so a fresh install has
bars that do nothing when clicked.

**What:**
- When the config loads, `hs.ipc.cliStatus(prefix)` checks for the command and
  `hs.ipc.cliInstall(prefix)` installs it if missing. An existing `hs` is left alone.
- prefix is `/opt/homebrew` when that folder exists (Apple Silicon Homebrew), else `/usr/local`.
- The rule lives in a module with no Hammerspoon dependency, tested with luajit.
- The doctor's fix for a missing `hs` becomes "reload Hammerspoon".
- README's Install section says Hammerspoon installs `hs` itself.

## 2. File search in the palette, behind a feature flag

**Why:** open a recent file from Option+Space without Finder. It must stay light: the user
wants it off unless turned on, and no work at all while off.

**Feature flags:**
- Defaults are committed in `hammerspoon/.hammerspoon/flags.lua`: `file-search` off.
- Overrides live in `~/.config/omv/flags`, outside the repo: one `name=on` or `name=off`
  per line; `#` starts a comment; unknown names and bad lines are ignored. A missing file means
  the defaults. Read when Hammerspoon loads, so a change needs a reload.
- This follows the common dotfiles pattern: committed defaults, an uncommitted local file
  loaded over them, falling back to the defaults when it's absent.

**Search, while `file-search=on`:**
- The palette asks for files once the typed text is 3 characters or more and typing has paused
  for 300ms.
- `mdfind -onlyin $HOME` for names containing the text, case- and accent-insensitive, among
  files opened **or modified** in the last 30 days. (Opened alone isn't enough: macOS records
  "last opened" only for files opened through Finder or apps, so a file edited in a terminal
  never counts. Measured here: 0.17–0.19s per search, relevant results.)
- Paths under `Library/`, `node_modules/` and `.git/` are dropped; at most 20 rows, under a
  "Files" heading after the other rows, labelled with the file name, hinted with its folder
  (`~/…`). Enter opens the file with its default app.
- Runs with `hs.task`, never blocking Hammerspoon. A newer search stops the one still
  running, and an answer for text that's no longer typed is dropped.
- Typed text reaches `mdfind` as an argument, never through a shell; `"`, `\` and `*` are
  removed from it so it can't change the query.
- While the flag is off: no Files heading, no message from the page, no `mdfind`.

**Approaches (flag):** a flags file outside the repo over committed defaults (picked) vs. a Lua
table in the repo (puts a personal choice into shared code) vs. a System menu switch (the user
wants a flag, not a switch).

**Approaches (search):** on demand while typing, as above (picked) vs. loading recent files
when the palette opens (one search per open even when no file is wanted).

**Non-goals:** searching file contents; folders; a flags UI; other flags.

## Left to the builder

The page's messages and functions, the row icon, and how stale answers are recognised.
