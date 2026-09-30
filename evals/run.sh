#!/bin/bash
# Runs the eval suite in three groups, each with its own stubs first on PATH:
# std-* (Mole 1.56.1 stub), old-* (Mole 1.50.0 stub), nomo-* (no Mole, brew stub).
# The removing Mole commands are granted so a skipped yes shows up in the trace
# instead of being denied; they reach only the stub. Extra args go to every run.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
stubs="$root/tests/eval-stubs"
claude_bin=$(command -v claude)
system_path=/usr/bin:/bin:/usr/sbin:/sbin
allow=(
  "Bash($root/skills/diskdiet/scripts/guard.sh *)" "Bash($root/skills/diskdiet/scripts/metrics.sh *)"
  "Bash($root/skills/diskdiet/scripts/freespace.sh *)"
  "Bash(mo *)" "Bash(brew install *)" "Bash(command -v *)" "Bash(printf *)"
  "Bash(mktemp -d \"\$TMPDIR/diskdiet-XXXXXX\")" "Bash(df -k *)" "Bash(diskutil apfs list)" "Bash(tmutil listlocalsnapshots *)"
  "Bash(mdls -name kMDItemCFBundleIdentifier -raw *)" Skill
)
# Results name local paths; keep them out of the product folder (privacy scan).
out=$(mktemp -d "${TMPDIR:-/tmp}/diskdiet-evals-XXXXXX")
# run <PATH> <case glob> [args]: fails unless every case passed; the eval
# command's own exit status does not say so.
run() {
  local json="$out/${2//\*/}.json"
  PATH="$1" "$claude_bin" plugin eval "$root" --case "$2" --ablation none --no-publish --trust-plugin \
    --allow-tools "${allow[@]}" --json "$json" "${@:3}"
  jq -e '.aggregates.casesPassed == .aggregates.casesTotal' "$json" >/dev/null
}
trap 'mv "$root/evals/results/"* "$out/" 2>/dev/null; rmdir "$root/evals/results" 2>/dev/null; echo "eval results: $out"' EXIT
# The removing commands are granted only while mo resolves to the stub inside a run.
run "$stubs/current:$PATH" std-precheck "$@" || { echo "precheck failed: mo is not the stub, stopping" >&2; exit 1; }
status=0
run "$stubs/current:$PATH" 'std-*' "$@" || status=1
run "$stubs/old:$PATH" 'old-*' "$@" || status=1
run "$stubs/nomo:$system_path" 'nomo-*' "$@" || status=1
exit $status
