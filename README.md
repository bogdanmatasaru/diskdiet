# diskdiet

[![CI](https://github.com/bogdanmatasaru/diskdiet/actions/workflows/ci.yml/badge.svg)](https://github.com/bogdanmatasaru/diskdiet/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Mole 1.56.1](https://img.shields.io/badge/Mole-1.56.1-orange.svg)](https://github.com/tw93/Mole)

**Put your Mac's disk on a diet, without losing anything you care about.**

A Claude Code plugin that audits and cleans a Mac step by step. It uses [Mole](https://github.com/tw93/Mole) (`mo`) for the analysis and the cleaning, shows a preview before anything is removed, and asks for a separate yes at every stage. It ends with health checks and a report you can compare with the next run.

## Why diskdiet

- **Safe by default.** Analysis changes nothing. Photos, app containers and iCloud Drive are protected, and every path is checked before a removing command runs.
- **Preview before delete.** Each stage shows exactly what Mole would remove, and nothing runs without your yes for that stage.
- **Proof, not promises.** A before/after report of free space, snapshots and swap, saved so the next run can compare.

## Install

```sh
claude plugin marketplace add bogdanmatasaru/diskdiet
claude plugin install diskdiet@diskdiet
```

Then in Claude Code, run `/diskdiet`. If Mole is missing, the skill asks before it runs `brew install mole`.

Requirements: macOS 15 or later (for `/usr/bin/jq`), Claude Code, and Mole 1.56.1 or later. Tested with Mole 1.56.1.

## Stages

| # | Stage | What happens |
| --- | --- | --- |
| 1 | Preflight | Checks `mo` and `jq`; asks before installing Mole |
| 2 | Analyse | `mo analyze`, local snapshots, free space, and a free-space target; changes nothing |
| 3 | Clean | Protects your paths in Mole's whitelist, previews `mo clean` and `mo purge`, runs them on a yes |
| 4 | Snapshots | Only when local Time Machine snapshots exist; deletes them on a yes |
| 5 | Large files | Lists the biggest files; never deletes them |
| 6 | Uninstall | Previews `mo uninstall` for the apps you pick; checks every path first |
| 7 | Optimize | Previews `mo optimize`; runs it on a yes |
| 8 | Sanity checks | Compares health before and after: free space, snapshots, swap, protected folders |
| 9 | Report | Writes `~/Library/Logs/diskdiet/<date>.md` and `.json`, compared with the last run |

Answer no at any stage and nothing runs for it; you then choose to go on or stop.

## Safety

- Every removing stage shows its preview first. "Do everything" or an earlier yes does not skip the next question.
- The skill itself never deletes files. Only Mole and `tmutil` remove data, and only after that stage's yes.
- Photos libraries, `~/Library/Containers`, iCloud Drive (`~/Library/Mobile Documents`) and Mole's default whitelist are never touched. The only exception is the containers of an app you choose to uninstall.
- `scripts/guard.sh` checks each path before a removing command, following symlinks. A refused path is dropped and named.
- The paths added to `~/.config/mole/whitelist` stay there after the audit, so plain `mo clean` protects them too.
- Adversarial evals (`evals/`) check that the skill refuses "skip the questions", "delete my Photos cache" and similar requests.

## Free-space target

The target is 40 GB plus 10 GB, plus swap in use, plus the caches Mole would clean, rounded up. The analyse stage shows the formula with your numbers and the gap to the target.

## Rollback

Remove the plugin, or the plugin and its marketplace:

```sh
claude plugin uninstall diskdiet@diskdiet
claude plugin marketplace remove diskdiet
```

Removing the marketplace also uninstalls every plugin installed from it. To go back to an earlier release, remove the marketplace, then add it again pinned to that release's tag with `#<tag>` and install:

```sh
claude plugin marketplace add bogdanmatasaru/diskdiet#<tag>
claude plugin install diskdiet@diskdiet
```

What an audit changed, and how to get it back:

| Stage | Where it goes | Recovery |
| --- | --- | --- |
| Clean (`mo clean`, `mo purge`) | Deleted, not moved to the Trash | Time Machine backup; caches and build folders are rebuilt by the apps that use them |
| Snapshots (`tmutil deletelocalsnapshots`) | Deleted | None; Time Machine takes new ones on its next backup |
| Uninstall (`mo uninstall`) | The Trash, until you empty it | Put Back from the Trash; the app's settings (`defaults` domain and ByHost preferences) are cleared and need a Time Machine backup |
| Optimize (`mo optimize`) | Maintenance tasks, nothing listed as removed | Time Machine backup |
| Whitelist (`~/.config/mole/whitelist`, `whitelist_optimize`) | Lines added, never removed | Delete the lines the clean stage showed; if the files did not exist before, delete them to return to Mole's defaults |
| Report (`~/Library/Logs/diskdiet/`) | New files | Delete them |

`mo history` lists what Mole removed or trashed, with paths.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues as described in [SECURITY.md](SECURITY.md).

## License

MIT, see [LICENSE](LICENSE). Mole is GPL-3.0 and installed separately; see [NOTICE](NOTICE).
