# doctor.sh --fix: find and clear a jammed Hammerspoon or bar

**Why:** on 2026-11-14 Hammerspoon stopped answering `hs -c`: about 170 `hs` calls from the
bar's Bluetooth item were stuck, and two SketchyBars ran, each polling. Finding that took a
long hunt; clearing it took three commands. The doctor should find it, and fix it on request.

## What

`./doctor.sh` gains three checks in its Running section, and stays read-only:
- **Hammerspoon answers:** `hs -c` gets 5 seconds (perl's `alarm`, as `bluetooth.sh` does),
  so the doctor itself can't hang on a jammed Hammerspoon. Today's config check moves under
  the same limit.
- **No stuck `hs` calls:** any `hs` process running for more than 60 seconds is stuck.
- **One SketchyBar:** more than one `sketchybar` process is a problem.

Each gives `fix: ./doctor.sh --fix`.

`./doctor.sh --fix` runs the same checks, but first clears what it can, saying each step:
1. kills stuck `hs` calls;
2. with more than one bar: stops them all and starts one;
3. if Hammerspoon still doesn't answer: quits and reopens it.

Then it runs the checks and reports as usual, so the output shows whether the fix worked.

## Approaches

- **A. `--fix` flag (picked):** plain `doctor.sh` keeps its read-only promise; the fix is
  one command you choose to run.
- B. Ask per problem: safer, but can't run from a script.
- C. Fix in the background from Hammerspoon: nothing to remember, but a background killer is
  harder to trust, and it can't help when Hammerspoon is the stuck one.

## Non-goals

Fixing the other problems the doctor finds (installs, links, settings): those keep their
printed `fix:` commands. The shared `hs` wrapper for click scripts and palette file search
are separate changes.

## Left to the builder

How the age of a process is read (`ps -o etime`), and the wording of each line.
