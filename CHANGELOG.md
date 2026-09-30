# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
