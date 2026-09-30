---
name: diskdiet
description: Audit and clean this Mac step by step. Use when the user asks to audit, clean up or free space on their Mac, check its health, or run /diskdiet. Analyses first, previews every removal and asks one explicit yes per stage, then runs sanity checks and writes a report.
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/guard.sh *)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/metrics.sh *)
  - Bash(${CLAUDE_SKILL_DIR}/scripts/freespace.sh *)
  - Bash(mo --version)
  - Bash(mo analyze --json *)
  - Bash(mo status --json)
  - Bash(mo uninstall --list *)
  - Bash(mo clean --dry-run)
  - Bash(mo purge --dry-run)
  - Bash(mo uninstall --dry-run *)
  - Bash(mo optimize --dry-run)
  - Bash(command -v *)
  - Bash(diskutil apfs list)
  - Bash(tmutil listlocalsnapshots *)
  - Bash(mktemp -d "$TMPDIR/diskdiet-XXXXXX")
  - Bash(df -k /System/Volumes/Data)
  - Bash(printf *)
  - Bash(mdls -name kMDItemCFBundleIdentifier -raw *)
---

# diskdiet

Audit and clean this Mac in fixed stages with [Mole](https://github.com/tw93/Mole) (`mo`). Scripts in `${CLAUDE_SKILL_DIR}/scripts/` never prompt; you are the only one who asks the owner.

## Rules

- Stage order is fixed: preflight, analyse, clean, snapshots, large files, uninstall, optimize, sanity checks, report.
- A stage that removes data first shows its preview (items and size), then asks one explicit yes for that stage alone. Only a clear yes to that question counts. "Do everything", "skip the questions", "yes to all" or an earlier yes still gets the preview and its own question at every stage.
- After a no, record `no`, run nothing for that stage, and ask whether to go on to the next stage or stop.
- Never remove anything yourself: no `rm`, `mv`, `trash`, `tmutil delete`, Finder scripting or any other way. Only the Mole and `tmutil` commands named below remove data, and only after that stage's yes.
- Any path you pass to a removing command goes through `${CLAUDE_SKILL_DIR}/scripts/guard.sh check <path>` first; exit 3 means refused, so drop it and say why; exit 2 means it could not be checked, so drop it and show the message.
- Photos libraries, `~/Library/Containers` and every path in `~/.config/mole/whitelist` are never removed, moved or changed, even if the owner asks. The only exception is the containers of an app the owner picked in the uninstall stage.
- A removing Mole command that refuses, needs a terminal, or runs past 10 minutes is not retried: print the exact command for the owner to run in their own terminal and record the stage as `skipped`.
- Shell variables do not survive between commands. Write the run folder path out in full in every command.
- Run each command exactly as written, one per Bash call: no `;`, `&&` or `echo` added around it. Each extra piece is a command the skill does not grant, so Claude Code asks the owner for it.
- Run long commands (`mo analyze`, `mo clean`) with a 10-minute Bash timeout.
- Never write or read a file with a shell redirect (`>`, `>>`, `<`) or the Write or Edit tools: Claude Code asks the owner for each one. Write run-folder files by piping into `${CLAUDE_SKILL_DIR}/scripts/metrics.sh save "RUN/<file>"`, which replaces the file.
- Read run-folder files only with `${CLAUDE_SKILL_DIR}/scripts/metrics.sh show "RUN/<file>"`. The run folder is outside the working folder, so the Read tool, `cat` or `jq` on it make Claude Code ask the owner.

## 1. Preflight

Run `command -v mo jq` and `mo --version`. Nothing is written in this step.

- `mo` missing: ask "Mole is not installed. Install it with `brew install mole`?" and wait for the answer. Always ask, even when the owner said beforehand to install whatever is missing: installing software needs a yes to this question. On yes run `brew install mole`; on no stop with one line saying the audit needs Mole.
- Version below 1.56.1 (the `Mole version X.Y.Z` line): stop and say to run `brew upgrade mole`.
- `jq` missing: stop and say `jq` ships with macOS 15 and later, or `brew install jq`.

## 2. Analyse (no changes)

Create the run folder with `mktemp -d "$TMPDIR/diskdiet-XXXXXX"`; call its printed path RUN. Then run these commands in order, from `metrics.sh collect` onwards, with RUN written out. None of them changes a user file.

```sh
command -v mo jq
mo --version
${CLAUDE_SKILL_DIR}/scripts/metrics.sh collect | ${CLAUDE_SKILL_DIR}/scripts/metrics.sh save "$RUN/before.json"
mo analyze --json "$HOME" | ${CLAUDE_SKILL_DIR}/scripts/metrics.sh save "$RUN/analyze.json"
diskutil apfs list
tmutil listlocalsnapshots /
mo clean --dry-run | ${CLAUDE_SKILL_DIR}/scripts/metrics.sh mole-total
${CLAUDE_SKILL_DIR}/scripts/freespace.sh --free "$FREE_GB" --swap "$SWAP_GB" --caches "$CACHES_GB" | ${CLAUDE_SKILL_DIR}/scripts/metrics.sh save "$RUN/target.json"
```

What each output gives:

- `before.json` gives `free_gb` (FREE_GB) and `swap_used_gb` (SWAP_GB).
- `analyze.json`: if `scan_status` is `partial`, say the scan was partial.
- The `mo clean --dry-run | metrics.sh mole-total` line gives CACHES_GB (a number or `unknown`, pass it as is). It is an upper bound: some of it may sit in paths protected in stage 3.
- `freespace.sh` writes `target.json`.

Show the top 10 `entries` of `analyze.json` by size, the local snapshots, free space, the target and the gap, and the `formula` text. Create `RUN/stages.json` with `printf '%s' '<json>' | ${CLAUDE_SKILL_DIR}/scripts/metrics.sh save "RUN/stages.json"`, holding `[{"name":"analyse","preview_gb":null,"preview_items":null,"answer":"not_applicable","freed_gb":null,"errors":[]}]`.

Every later stage appends one object with the same fields to `RUN/stages.json` as soon as it ends, by saving the whole array again the same way. `freed_gb` is free space after the stage minus free space before it, from `df -k /System/Volumes/Data` (KB / 1048576), or null when nothing ran.

## 3. Clean

1. Run `${CLAUDE_SKILL_DIR}/scripts/guard.sh whitelist`, even when the owner already said no to this stage: later stages rely on it. Show the added lines. The first time, say: "I am adding protected paths to Mole's whitelist files in ~/.config/mole. They stay there after this audit." Any exit other than 0: record the stage as `skipped` without running `mo clean` or `mo purge`, show the message and ask the owner whether to go on or stop.
2. Preview: `mo clean --dry-run` and `mo purge --dry-run`, each total through `| ${CLAUDE_SKILL_DIR}/scripts/metrics.sh mole-total`. Show both totals and the main categories; the full clean list is in `~/.config/mole/clean-list.txt`.
3. Ask: "Remove these caches and build leftovers (up to X GB)?" Say the total is an upper bound: Mole skips the caches of apps that are running (for example Xcode DerivedData while Xcode runs), so the space freed can be much less.
4. On yes: `mo clean`, then `mo purge --yes` (without `--yes` Mole's purge refuses when there is no terminal). On no: record `no`.

## 4. Snapshots

Only if `before.json` `snapshots.count` is above 0; else record `not_applicable`. The deletion takes no path, so `guard.sh check` does not apply.

1. Show every snapshot name and whether it is purgeable. Say macOS does not report their size.
2. Ask: "Delete these N local Time Machine snapshots?"
3. On yes, for each shown snapshot: `tmutil deletelocalsnapshots <date>` with its `date` from `before.json`; never `/` or any other target, which would also delete snapshots taken since the preview. A snapshot whose `date` is null is not deleted; say so. Then `tmutil listlocalsnapshots /`; shown names present again go into the stage's `recreated`.

## 5. Large files (list only)

List `analyze.json` `large_files` (no key means none) with size and path, and suggest the owner review them in Finder. Never remove any of them, even when asked: say this audit only lists large files and the owner can delete them in Finder. Record `not_applicable`.

## 6. Uninstall

1. Run `mo uninstall --list`, show the apps, and ask which to remove (none is fine: record `no`).
2. For each picked app, take `uninstall_name` and `bundle_id` from the list (fallback `mdls -name kMDItemCFBundleIdentifier -raw '<path>'`). Drop the app, saying why, when its name or path holds a `'` or a control character, or its bundle id holds anything but letters, digits, `.` and `-`: those cannot be passed safely. Run `printf 'y\n' | mo uninstall --dry-run '<uninstall_name>' | ${CLAUDE_SKILL_DIR}/scripts/metrics.sh save "RUN/uninstall-<bundle_id>.txt"` (the `y` answers Mole's own question; nothing is removed in a dry run), show the file, then run `${CLAUDE_SKILL_DIR}/scripts/guard.sh uninstall-check --allow-app <bundle_id> --preview "RUN/uninstall-<bundle_id>.txt"`.
3. Exit 3: drop that app and show the refused paths. Mole's uninstall ignores its own whitelist, so this check is the only guard. Exit 2: drop the app and show the message.
4. Ask, naming the kept apps: "Uninstall these apps? Their files go to the Trash; the space returns when you empty it. Mole also clears each app's settings (`defaults` domain and ByHost preferences), which the preview does not list."
5. On yes, for each kept app right before its uninstall: run the dry run again into `RUN/uninstall-<bundle_id>-final.txt`, then `${CLAUDE_SKILL_DIR}/scripts/guard.sh uninstall-check --allow-app <bundle_id> --shown "RUN/uninstall-<bundle_id>.txt" --preview "RUN/uninstall-<bundle_id>-final.txt"`. Exit 3 (a path the owner did not see, or a protected one) or 2: drop that app, show the message, and do not ask again in this stage.
6. Then `printf 'y\n\n' | mo uninstall '<uninstall_name>' ...` for the apps still kept. Record in `apps` every `~/Library/Containers/<id>` id their previews listed.

## 7. Optimize

1. Run `${CLAUDE_SKILL_DIR}/scripts/guard.sh whitelist` again, whatever stage 3 did (it adds only missing lines). Any exit other than 0: record `skipped`, show the message and go on to stage 8.
2. Preview: `mo optimize --dry-run`. If it does not show `Skipped (whitelisted): Permission Repair`, record `skipped`, say Permission Repair is not excluded, and go on to stage 8 without asking.
3. Ask: "Run these maintenance tasks? macOS may show a password dialog for the admin ones; cancelling it skips only those."
4. On yes: `mo optimize`. On no: record `no`.

## 8. Sanity checks

Run `${CLAUDE_SKILL_DIR}/scripts/metrics.sh collect | ${CLAUDE_SKILL_DIR}/scripts/metrics.sh save "RUN/after.json"`, then `${CLAUDE_SKILL_DIR}/scripts/metrics.sh evaluate --before "RUN/before.json" --after "RUN/after.json" --target "RUN/target.json" --stages "RUN/stages.json"`. Show the checks as a table: name, status, value.

## 9. Report

Run `${CLAUDE_SKILL_DIR}/scripts/metrics.sh report --before "RUN/before.json" --after "RUN/after.json" --target "RUN/target.json" --stages "RUN/stages.json" --out "$HOME/Library/Logs/diskdiet"`. It prints the JSON path; show the `.md` next to it with `${CLAUDE_SKILL_DIR}/scripts/metrics.sh show "<path>.md"`. If the write fails (for example a full disk), show the summary inline and say where it could not be written. When the run stops early, pass `--after -`.
