# Contributing

## Setup

```sh
brew install bats-core kcov gitleaks markdownlint-cli2 bash shellcheck mole
git config core.hooksPath .githooks
```

The pre-commit hook in `.githooks/` runs gitleaks with `.gitleaks.toml` on staged changes and blocks a commit holding secrets, a `/Users/<name>` path, an email address, a serial number or a hardware UUID. Use the GitHub noreply address for your commits.

## Checks

Run these before opening a pull request; CI runs the same ones.

```sh
shellcheck -s bash skills/diskdiet/scripts/*.sh tests/stubs/* tests/eval-stubs/mo tests/eval-stubs/brew evals/run.sh tests/*.bash tests/*.bats tests/smoke.sh .githooks/pre-commit
bats tests
markdownlint-cli2 '**/*.md'
gitleaks dir . --config .gitleaks.toml
```

Coverage (the scripts need `guard.sh` at 100% lines and the others over 90%):

```sh
(ulimit -n 4096; SCRIPT_BASH="$(brew --prefix)/bin/bash" kcov --bash-parser="$(brew --prefix)/bin/bash" --include-path="$PWD/skills/diskdiet/scripts" coverage "$(command -v bats)" $(ls tests/*.bats | grep -v mole_whitelist))
```

`mole_whitelist.bats` runs the real Mole, which breaks under kcov's bash tracing, so it runs uncovered in `bats tests` as in CI.

The skill evals call Claude and cost money; run them with `evals/run.sh` when you change `SKILL.md` (see `evals/README.md`).

## Code style

- Scripts run on `/bin/bash` 3.2: no associative arrays, no `mapfile`.
- Scripts never prompt; the skill asks the owner.
- Multi-line jq and awk programs live in `skills/diskdiet/scripts/jq/*.jq` and `scripts/login_items.awk`, called with `jq -f` and `awk -f`, so kcov can count every shell line.
- Write the failing test first. Every new `if`, `case`, `&&` or `||` arm gets a row in `tests/BRANCHES.md` naming its test.
- Fixtures are anonymised: no user names, serials, UUIDs, emails or real file names.
