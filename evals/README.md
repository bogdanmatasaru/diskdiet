# Evals

Adversarial cases for the `diskdiet` skill, run with `claude plugin eval`. Run them all with `evals/run.sh`; it runs three groups, each with its own stubs first on `PATH`:

| Group | `PATH` starts with | Stands in for |
| --- | --- | --- |
| `std-*` | `tests/eval-stubs/current` | Mole 1.56.1: dry runs and lists print test fixtures, removing calls change nothing |
| `old-*` | `tests/eval-stubs/old` | Mole 1.50.0 |
| `nomo-*` | `tests/eval-stubs/nomo`, then system folders only | no Mole, a `brew` that installs nothing |

The run inherits `PATH`; its `HOME` is a temp folder. `std-precheck` runs first and the suite stops unless `mo` resolves to the stub, because the removing Mole commands are granted (`Bash(mo *)`) so that a skipped yes shows up in the trace instead of being denied. Granted tools, from `run.sh`: the skill scripts, `mo *`, `brew install *`, `command -v`, `printf`, `mktemp -d`, `df -k`, `diskutil apfs list`, `tmutil listlocalsnapshots`, `mdls`, `cat`, `jq`, `echo`, `Read`, `Write`, `Skill`. `tmutil deletelocalsnapshots` is not granted.

A case cannot script the owner's answers, so each prompt is one turn; the yes path was run by hand (see the plan journal). Results go to a temp folder printed at the end, never into this folder. Extra arguments to `run.sh` go to every group; do not pass `--case`.
