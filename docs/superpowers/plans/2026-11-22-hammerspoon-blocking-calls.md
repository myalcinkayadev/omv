# Blocking calls in Hammerspoon

Found on 2026-11-22 while testing the window card (Option+W). To do after the workspace model
branch is merged.

## Why it matters

Hammerspoon runs all Lua on its main thread. While a call there waits, every card freezes: it
can't scroll, take a key or redraw. Two things cause it in omv.

1. **Synchronous shell calls** (`hs.execute`, `os.execute`, `hs.osascript.applescript`,
   `io.popen`, `:waitUntilExit()`): the thread waits for the command to finish.
2. **`hs` calls cut off mid-print.** hs.ipc sends console output to each connected `hs`
   command. Sending to one that already quit raises before hs.ipc unmarks it as printing, so
   every print after that warns through the logger, which prints, and recurses until the stack
   overflows: 0.5 to 5 seconds per print, worse with each call cut off.
   `config/hammerspoon/ipcguard.lua` now clears those marks after a failed send. The callers
   below should still stop cutting calls off.

The fix for 1 is `hs.task` with a callback, as `features/workspaces.lua` does since this branch:
see its `aerospace(arguments, done)` and `moveWindows`.

Sources: [independent Lua threads in Hammerspoon](https://groups.google.com/g/hammerspoon/c/JvdSiCUaxYU),
[Hammerspoon issue #3742](https://github.com/Hammerspoon/hammerspoon/issues/3742),
[hs.ipc source](https://cdn05042023.gitlink.org.cn/dnrops/hammerspoon/src/branch/track-lua-threads/extensions/ipc/ipc.lua).

## 1. `hs` calls that can be cut off

| Place | Call | How often |
|---|---|---|
| `config/sketchybar/.config/sketchybar/plugins/bluetooth.sh:20` | `perl -e "alarm …" hs -c 'return omvBluetoothPower()'` | On the bar's timer; the most likely one |
| `config/sketchybar/.config/sketchybar/sketchybarrc:276` | `hs -t 2 -c 'omvRedrawBar()' &` | Each bar reload |
| `config/aerospace/.config/aerospace/aerospace.toml:27` | `hs -t 2 -c "omvWorkspaceChanged(…)"` | Each workspace switch, while a workspace has `open` |
| `bin/omv:72` `hs_call` (used at `:77`, `:147`, `:325`) | `perl alarm … hs -t N` | `omv reload`, `omv update`, `omv theme` |
| `install/doctor.sh:218` | `perl alarm … hs -c` | `omv doctor` |

The bar's click scripts (`hs -c 'omvToggle…()'`, about 20) have no timeout, but can still leave
a mark when their script is killed.

Options: read Bluetooth's power in the bar plugin itself (`blueutil -p`) instead of asking
Hammerspoon; use `hs -q` or `hs.ipc` without console mirroring where the output isn't read;
or keep the guard and accept it.

## 2. Synchronous calls on Hammerspoon's thread

| Place | Waits on | Risk |
|---|---|---|
| `features/agents.lua:59, 113, 120, 122` | `claude agents --json`, `claude daemon …` | High: a Node CLI, often seconds |
| `features/devlayout.lua:39, 43, 47, 90, 101, 148, 183` | `aerospace`, `git rev-parse`, `tmux`, the editor command | High when opening a layout |
| `features/meeting.lua:48, 62` | AppleScript to Music or Spotify | High: waits on the player, seconds when it's busy or starting |
| `features/meeting.lua:68` | `aerospace list-windows` | Low |
| `features/procs.lua:27, 50` | `lsof` for working folders and listening ports | Medium: `lsof` can take a second or more |
| `features/procs.lua:15, 31` | `id -u`, `ps` | Low |
| `features/waiting.lua:67, 86, 89, 90` | `ps`, `tmux` | Medium: when jumping to an agent |
| `features/network.lua:33, 56, 57` | `route`, `networksetup`, `ifconfig` per port | Medium: `networksetup` is slow |
| `features/bluetooth.lua:17` | `blueutil` | Medium: hangs when Bluetooth is slow |
| `features/battery.lua:17, 19` | `pmset`, `ioreg` | Low to medium |
| `features/disk.lua:110, 124` | `df` | Low |
| `features/claudeprojects.lua:18` | `ls -t … \| head` over `~/.claude/projects` | Medium with many projects |
| `features/theme.lua:51` | `pgrep borders` | Low |
| `shell.lua:184` | `sketchybar --query` | Low |
| `os.execute` in procs, waiting, sound, micmute, reminders, theme, windows, setups, workspaces | mostly `mkdir -p` and `kill` | Low |

## Plan

1. Measure first: a stall detector (an `hs.timer.doEvery(0.05)` noting gaps over 0.25 s) that
   writes to a file, never to the console, while using each card.
2. Convert the high and medium rows to `hs.task` with callbacks, one feature per commit, worst
   first: agents, devlayout, meeting, procs, network, bluetooth, waiting.
3. Change the `hs` callers in section 1 so they don't cut calls off.
4. Keep `ipcguard.lua` as the safety net.
