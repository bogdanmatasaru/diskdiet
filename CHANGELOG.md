# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.0] - 2026-11-09

### Added

- `leftovers.sh` finds five more kinds of leftovers: uv's cache (`uv-cache`), Xcode DerivedData of projects not built for 30 days (`xcode-derived-data`; Mole skips all of DerivedData while Xcode runs), git worktrees under `~/Projects` unchanged for 30 days with no changed, untracked, ignored or skip-worktree file, no submodule, and every commit on a remote or the main worktree's HEAD (`git-worktrees`, removed with `git worktree remove`; repos whose own config sets filters, diff drivers, includes, a partial clone, remote programs or an ssh command are not scanned, nor worktrees with submodules, and git runs with fsmonitor, hooks and lazy fetches off), and simulator devices shut down and unused for 30 days (`simulator_devices` in the list, `simulator-devices` removed with `xcrun simctl delete` after `guard.sh` checks each device folder).
- `leftovers.sh list --max` and `remove --max <id>...` drop the 30-day rule for simulators and DerivedData: every shut-down simulator device not used in the last 2 hours, all of DerivedData, and every ready simulator runtime but the newest of its platform, unless used in the last 2 hours or a booted simulator runs on it (deleted one by one with `xcrun simctl runtime delete <id>`). The skill uses it when the owner asks to free as much as possible or the target is not met.
- New leftovers: `xcode-previews` (Xcode UserData/Previews), `xcodebuildmcp`, `tmpdir-temp` (`$TMPDIR/tmp.*` and `pytest-of-*`), `npm-cache` (`~/.npm/_cacache`) and `project-build-dirs` (build output folders under `~/Projects` that git ignores and that hold no tracked file and no git checkout of their own, for when `mo purge` runs out of time).
- The clean stage previews `mo purge` again with `MO_PURGE_SCAN_TIMEOUT_SEC=600` when Mole reports `Dry run incomplete`, so build folders in big project trees are no longer missed.

### Changed

- The free-space target is the owner's choice: `freespace.sh --total GB --free GB --max-used-pct N` keeps the disk at most N% used, replacing the fixed 40+10+swap+caches formula. `--swap` and `--caches` are gone.
- `leftovers.sh list` checks the temp folders with one `find` and measures every unit not in use with one `du -l`, instead of three processes per unit (2,000 temp folders list in about 1 s); a hard-linked file counts in every unit that holds it.
- Simulator devices are deleted one `simctl delete` at a time, skipping any whose folder changed in the last 2 hours; each failure names its device.
- `restart_gb` leaves out Chrome's `code_sign_clone` folders, which share their blocks with Chrome (deleting 109 of them freed 0 GB), and the temp folders listed as `tmpdir-temp`.
- `restart_gb` is shown as an upper bound: `du` counts APFS clones in macOS temp folders in full.

## [0.3.0] - 2026-10-19

### Added

- A developer leftovers stage after clean. The new `leftovers.sh list` measures what Mole does not clean: Android emulators and system images, LM Studio models, Xcode device support, Playwright browsers, Gradle caches, the Claude desktop VM bundle and Claude Code's temp folder, plus old simulator runtimes and the space a restart frees. `leftovers.sh remove <id>...` removes the ids the owner picks, skipping every path `guard.sh` refuses and every path changed in the last 120 minutes. `DISKDIET_CLAUDE_TMP` overrides the Claude Code temp folder; the folder is skipped when it is a symlink or not owned by you.

## [0.2.2] - 2026-09-30

### Fixed

- The skill ran some commands chained with `;`, `&&` or `echo`, which the skill does not grant, so Claude Code asked the owner or, in headless mode, denied them. SKILL.md now says to run each command exactly as written, one per Bash call, and the eval runner no longer grants `echo`.

## [0.2.1] - 2026-09-30

### Fixed

- Installed from GitHub, the skill stopped at the analyse stage: it read its own command list and the run-folder JSON files, both outside the working folder, so Claude Code asked for every read or, in headless mode, denied it. The analyse commands now live in SKILL.md, and run-folder files and the final report are read with the new `metrics.sh show`.
- The eval runner no longer grants Read, `cat` or `jq`, so the evals see the same permissions as a real install.
- CI runs `brew update` before installing, so it tests the current Mole release instead of the runner's stale 1.53.0.

## [0.2.0] - 2026-09-30

### Fixed

- The clean stage question calls its total an upper bound, since Mole skips the caches of running apps such as Xcode DerivedData.
- README has a Rollback section: uninstalling, pinning an earlier release, and what each stage deletes or moves to the Trash.
- The skill writes run-folder files with the new `metrics.sh save` and gives `guard.sh uninstall-check` its preview with `--preview`, so no shell redirect makes Claude Code ask for permission during the audit.
- The snapshot stage deletes each shown Time Machine snapshot by its date instead of `tmutil deletelocalsnapshots /`, which also deleted snapshots taken after the preview; `metrics.sh collect` gives each snapshot its `date`.
- The uninstall stage passes app names and paths single-quoted and drops an app whose name, path or bundle id cannot be passed safely.
- `guard.sh whitelist` also excludes each `mo optimize` task whose files a protected path covers; Mole checks its path whitelist in almost none of them.
- The uninstall stage repeats the dry run right before the real uninstall and drops an app whose new preview lists a path the owner did not see (`guard.sh uninstall-check --shown`); the question now says Mole also clears the app's settings.
- `guard.sh uninstall-check` refuses Homebrew casks: Mole removes them with `brew uninstall --cask --zap`, whose paths the preview does not list.
- `guard.sh` exits 2, never 1, on any unexpected failure, such as an unwritable `~/.config/mole` or an unreadable whitelist.
- `metrics.sh report` renders the Markdown before writing and exits 2 when it cannot, instead of leaving an empty or cut-off `.md`; unknown free space and single-value stage notes now render.
- `allowed-tools` grants each helper script by name; `scripts/*` also pre-approved any binary reached through `scripts/../..`.
- `allowed-tools` grants `mdls` and `mktemp` only in the exact forms the skill uses; `mdls -plist` could overwrite any file without a prompt.
- `allowed-tools` grants the Mole dry runs only without extra flags; `mo purge --dry-run --paths` wrote a config file and opened an editor without a prompt.
- `guard.sh` exits 2 when a Mole whitelist path exists but is not a regular file.
- The skill refills Mole's whitelist before the optimize stage and skips optimize unless Permission Repair is excluded.

### Changed

- Renamed from mac-audit to diskdiet: the command is `/diskdiet`, reports go to `~/Library/Logs/diskdiet/`, and the environment overrides are `DISKDIET_JQ` and `DISKDIET_MOLE_LIB`.
- jq and awk programs moved out of the scripts into `scripts/jq/*.jq` and `scripts/login_items.awk`.

## [0.1.0]

### Added

- `/diskdiet` skill: preflight, analyse, clean, snapshots, large files, uninstall, optimize, sanity checks and report, with a preview and a separate yes at every removing stage.
- `guard.sh`: path checks against protected paths and Mole's whitelist, whitelist seeding, and uninstall preview checks.
- `metrics.sh`: health metrics, sanity checks and the before/after report with history.
- `freespace.sh`: free-space target and gap.
- bats tests, adversarial skill evals, gitleaks privacy gate and CI.
