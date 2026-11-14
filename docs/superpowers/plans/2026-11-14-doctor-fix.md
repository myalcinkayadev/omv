# doctor.sh --fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `./doctor.sh` finds a jammed Hammerspoon, stuck `hs` calls and a second SketchyBar; `./doctor.sh --fix` clears them.

**Architecture:** Three new checks at the end of `check_running` in `doctor.sh`, plus a `fix_running` step that runs before the checks when `--fix` is given. Every `hs -c` the doctor makes gets a time limit through perl's `alarm`, as `plugins/bluetooth.sh` does.

**Tech Stack:** bash, tested with `tests/doctor_test.sh` against stubs (`tests/lib.sh`).

**Spec:** `docs/superpowers/specs/2026-11-14-doctor-fix-design.md`

## Global Constraints

- Plain `./doctor.sh` changes no setting, link or process. Only `--fix` kills or starts anything.
- `hs -c` gets `OMV_HS_SECONDS` seconds, 5 unless a test sets it: `perl -e "alarm $seconds; exec @ARGV" hs -c …`.
- An `hs` process is stuck when it has run more than 60 seconds.
- Every new problem gives `fix: ./doctor.sh --fix`.
- Processes are killed through `xargs kill` and the bar is started with `nohup sketchybar`, so both go through `PATH` (stubbable in tests; `kill` is a shell builtin otherwise).
- Process ages come from `ps -axo pid=,etime=,command=`; `etime` reads `[[dd-]hh:]mm:ss`.

## Review Focus

1. The doctor's own `hs -c` must never count as a stuck call: the age check runs before the doctor asks Hammerspoon anything.
2. An `hs` the user is running by hand in another terminal (e.g. `hs` REPL, no `-c`) older than 60s: only `hs -c` calls count as stuck.
3. `--fix` when nothing is wrong: no kill, no restart, same report as plain `doctor.sh`.
4. `--fix` when SketchyBar isn't running at all: it's reported as not running (existing check); `--fix` does not start one (out of scope: not a jam).
5. Hammerspoon not running at all: today's "is not running" check covers it; `--fix` doesn't reopen what was never open.

---

### Task 1: The checks (read-only)

**Files:**
- Modify: `doctor.sh` (`check_running`, header comment)
- Test: `tests/doctor_test.sh`

**Interfaces:**
- Produces: `hs_answer()` prints the last line of `hs -c "$1"` within the time limit (empty when it times out); `stuck_hs_pids()` prints one pid per stuck `hs -c` call; `bar_count()` prints the number of `sketchybar` processes (`pgrep -x sketchybar | wc -l`).

- [ ] **Step 1: Write the failing tests.** `complete_setup` gains a `ps` stub that prints `$SANDBOX/ps` (empty by default) and a `pgrep` stub that prints one pid for `-x sketchybar` and exits 0 otherwise. Cases:
  - should flag Hammerspoon when hs hangs: `hs` stub `exec sleep 30`, `OMV_HS_SECONDS=1` → report contains `✗ Hammerspoon isn't answering — fix: ./doctor.sh --fix`, and `doctor` returns within 15s.
  - should flag a stuck hs call when one runs over 60s: `$SANDBOX/ps` has `4242 01:01 hs -c return omvBluetoothPower()` → `✗ 1 stuck hs call — fix: ./doctor.sh --fix`.
  - should read a stuck call's age in days: `4242 1-02:03:04 hs -c x` → `✗ 1 stuck hs call`.
  - should read a stuck call's age in hours: `4242 02:03:04 hs -c x` → `✗ 1 stuck hs call`.
  - should ignore an hs call under 60s old: `4242 00:59 hs -c x` → no `stuck hs call` in the report.
  - should ignore an hs that isn't a -c call: `4242 05:00 hs` → no `stuck hs call`.
  - should flag two bars when two run: `pgrep -x sketchybar` prints two pids → `✗ 2 SketchyBars are running — fix: ./doctor.sh --fix`.
  - should kill nothing without --fix: stuck call and two bars → no `kill` and no `pkill` line in `$CALL_LOG`.
  - should pass every check on a complete setup (existing) still passes.
- [ ] **Step 2: Run `bash tests/doctor_test.sh`.** Expected: the new cases FAIL, the old ones pass.
- [ ] **Step 3: Implement** `hs_answer`, `stuck_hs_pids`, `bar_count` and the three checks in `check_running`, in this order: stuck calls, bar count, Hammerspoon answers, then the existing config check through `hs_answer`. Ok lines: `no stuck hs calls`, `one SketchyBar`, `Hammerspoon answers`.
- [ ] **Step 4: Run `bash tests/doctor_test.sh`.** Expected: all `ok`.
- [ ] **Step 5: Commit** `feat: find a jammed Hammerspoon or bar`

### Task 2: `--fix`

**Files:**
- Modify: `doctor.sh` (argument handling, `fix_running`, header comment)
- Modify: `README.md` (Doctor section)
- Test: `tests/doctor_test.sh`

**Interfaces:**
- Consumes: Task 1's `stuck_hs_pids`, `bar_count`, `hs_answer`.
- Produces: `fix_running()`, run before the checks when `$1 = --fix`. Any other argument: print `usage: ./doctor.sh [--fix]` to stderr and exit 2.

- [ ] **Step 1: Write the failing tests:**
  - should kill stuck hs calls with --fix: stuck pid 4242 → `$CALL_LOG` has `kill 4242`, output has `→ killed 1 stuck hs call`.
  - should restart the bar with --fix when two run → `$CALL_LOG` has `pkill -x sketchybar` then `nohup sketchybar`, output has `→ restarted SketchyBar`.
  - should reopen Hammerspoon with --fix when it doesn't answer: hanging `hs` → `$CALL_LOG` has `pkill -x Hammerspoon` then `open -a Hammerspoon`, output has `→ reopened Hammerspoon`.
  - should leave Hammerspoon alone with --fix when it answers → no `Hammerspoon` in any `pkill`/`open` line.
  - should change nothing with --fix on a healthy setup → no `kill`, `pkill`, `nohup` or `open` line; exit 0.
  - should start no bar with --fix when none runs: `pgrep -x sketchybar` prints nothing → no `nohup` line (Review Focus 4).
  - should not open Hammerspoon with --fix when it isn't running: `pgrep -x Hammerspoon` exits 1, hanging `hs` → no `open -a Hammerspoon` (Review Focus 5).
  - should refuse an unknown argument: `--fxi` → exit 2, stderr `usage: ./doctor.sh [--fix]`.
- [ ] **Step 2: Run `bash tests/doctor_test.sh`.** Expected: the eight FAIL.
- [ ] **Step 3: Implement `fix_running`**, steps in order: kill stuck calls; if `bar_count` > 1, `pkill -x sketchybar`, wait until none is left (up to 5s), `nohup sketchybar >/dev/null 2>&1 &`; if Hammerspoon is running (`pgrep -x Hammerspoon`) and `hs_answer 'return 1'` isn't `1`, `pkill -x Hammerspoon`, wait until gone (up to 5s), `open -a Hammerspoon`, then wait up to 10s for it to answer. Printed under a `Fixing` section. README: one paragraph on `--fix` in the Doctor section; "It only reads" becomes "Without `--fix` it only reads".
- [ ] **Step 4: Run `bash tests/run.sh`.** Expected: exit 0.
- [ ] **Step 5: By hand:** `./doctor.sh` on this Mac → the three new ok lines; `./doctor.sh --fix` on the healthy Mac → no `→` lines, same report.
- [ ] **Step 6: Commit** `feat: clear a jammed Hammerspoon or bar with --fix`
