setup() {
  load helpers
  SKILL_MD="$TESTS_DIR/../skills/diskdiet/SKILL.md"
}

# Commands that remove data or install software; the harness must always ask.
REMOVING=(
  "mo clean" "mo purge --yes" "mo uninstall Foo" "mo optimize"
  "tmutil deletelocalsnapshots /" "tmutil deletelocalsnapshots 2026-09-01-120000" "tmutil thinlocalsnapshots /"
  "rm -rf /tmp/x" "brew install mole"
  "\${CLAUDE_SKILL_DIR}/scripts/../../../../bin/rm -rf x"
  "mo purge --dry-run --paths" "mo clean --dry-run --whitelist"
  "mdls -plist ~/.config/mole/whitelist /bin/ls" "mktemp -d ~/.config/mole/whitelist"
)

allowed_bash() { sed -n '/^allowed-tools:/,/^[^ ]/p' "$1" | sed -n 's/^  - Bash(\(.*\))$/\1/p'; }

# granted <command> <skill.md>: some allowed-tools Bash pattern matches the command.
granted() {
  local pattern
  while IFS= read -r pattern; do
    # shellcheck disable=SC2053 # the pattern is a glob on purpose
    [[ $1 == $pattern ]] && return 0
  done < <(allowed_bash "$2")
  return 1
}

@test "allowed-tools grants no removing or installing command" {
  [ -n "$(allowed_bash "$SKILL_MD")" ]
  for cmd in "${REMOVING[@]}"; do
    if granted "$cmd" "$SKILL_MD"; then
      echo "granted: $cmd" >&2
      return 1
    fi
  done
}

@test "allowed-tools lint catches a planted removing pattern" {
  sed 's/^  - Bash(mo clean --dry-run)$/  - Bash(mo clean*)/' "$SKILL_MD" >"$BATS_TEST_TMPDIR/SKILL.md"
  granted "mo clean" "$BATS_TEST_TMPDIR/SKILL.md"
}

@test "allowed-tools still grants the dry runs and helper scripts" {
  for s in 'guard.sh check x' 'guard.sh whitelist' 'metrics.sh collect' 'freespace.sh --free 1'; do
    granted "\${CLAUDE_SKILL_DIR}/scripts/$s" "$SKILL_MD"
  done
  granted "mo clean --dry-run" "$SKILL_MD"
  granted "mktemp -d \"\$TMPDIR/diskdiet-XXXXXX\"" "$SKILL_MD"
  granted "mdls -name kMDItemCFBundleIdentifier -raw /Applications/Foo.app" "$SKILL_MD"
  granted "mo uninstall --dry-run Foo" "$SKILL_MD"
}

@test "app names and paths reach shell commands single-quoted" {
  run grep -nE '(mo uninstall|mdls)[^`]*"<' "$SKILL_MD"
  [ "$status" -eq 1 ]
  grep -qF "mo uninstall --dry-run '<uninstall_name>'" "$SKILL_MD"
  grep -qF "mo uninstall '<uninstall_name>'" "$SKILL_MD"
  grep -qF "mdls -name kMDItemCFBundleIdentifier -raw '<path>'" "$SKILL_MD"
  granted "mo uninstall --dry-run 'Foo Bar'" "$SKILL_MD"
  granted "mdls -name kMDItemCFBundleIdentifier -raw '/Applications/Foo Bar.app'" "$SKILL_MD"
}

@test "snapshots are deleted one shown date at a time, never by volume" {
  run grep -nE 'tmutil deletelocalsnapshots /`' "$SKILL_MD"
  [ "$status" -eq 1 ]
  grep -qF 'tmutil deletelocalsnapshots <date>' "$SKILL_MD"
}

@test "SKILL.md redirects no file; writes go through metrics.sh save" {
  # shellcheck disable=SC2016 # a literal $RUN in the pattern
  run grep -nE '(^|[^0-9&])[<>] *"?(RUN|\$RUN)/' "$SKILL_MD"
  [ "$status" -eq 1 ]
  granted "\${CLAUDE_SKILL_DIR}/scripts/metrics.sh save \"/tmp/diskdiet-abc123/before.json\"" "$SKILL_MD"
  granted "mo analyze --json \"\$HOME\"" "$SKILL_MD"
}

@test "snapshot stage runs only when snapshots exist, else is recorded not_applicable (US2.4)" {
  stage=$(sed -n '/^## 4\. Snapshots/,/^## 5\./p' "$SKILL_MD")
  # shellcheck disable=SC2016 # literal backticks from SKILL.md
  grep -qF 'Only if `before.json` `snapshots.count` is above 0; else record `not_applicable`.' <<<"$stage"
}
