# Migrations

Scripts here make changes a pull alone can't, such as moving a file or renaming a package.
`omv update` and `omv install` run each one once, in name order, with bash; the ones that ran
are listed in `~/.local/state/omv/migrations`.

- Name: `<YYYYMMDDHHMM>-<what-it-does>.sh`, so name order is the order they were written.
- Safe on a fresh setup and safe to run twice: `omv install` runs every migration on a Mac
  that never had the old layout, and one that fails runs again on the next update. Check
  before changing (`[ -e old ] || exit 0`).
- Start with `set -euo pipefail`: a step that fails must fail the migration, so it isn't
  recorded as done.
- `omv update --undo` refuses after an update that ran a migration, since resetting the code
  can't reverse it.
