setup() {
  load helpers
  PRODUCT_DIR=$(cd "$TESTS_DIR/.." && pwd)
  CONFIG="$PRODUCT_DIR/.gitleaks.toml"
}

@test "every planted control is caught by its own rule" {
  local dir="$BATS_TEST_TMPDIR/controls" report="$BATS_TEST_TMPDIR/report.json" f rule
  mkdir "$dir"
  cp "$TESTS_DIR"/privacy/*.txt "$dir/"
  run gitleaks dir "$dir" --config "$CONFIG" --no-banner --report-format json --report-path "$report"
  [ "$status" -eq 1 ]
  for f in "$TESTS_DIR"/privacy/*.txt; do
    rule=$(basename "$f" .txt)
    /usr/bin/jq -e --arg r "$rule" --arg f "$rule.txt" \
      'any(.[]; .RuleID == $r and (.File | endswith("/" + $f)))' "$report"
  done
}

@test "product folder has no leaks" {
  run gitleaks dir "$PRODUCT_DIR" --config "$CONFIG" --redact --no-banner
  [ "$status" -eq 0 ]
}

@test "pre-commit hook blocks a staged user home path" {
  local repo="$BATS_TEST_TMPDIR/repo"
  mkdir "$repo"
  cp -R "$PRODUCT_DIR/.githooks" "$PRODUCT_DIR/.gitleaks.toml" "$repo/"
  cd "$repo"
  git init -q
  git config core.hooksPath .githooks
  git config user.name test
  git config user.email test@example.com
  cp "$TESTS_DIR/privacy/user-home-path.txt" leak.txt
  git add leak.txt
  run git commit -q -m leak
  [ "$status" -ne 0 ]
  git rm -q --cached leak.txt
  printf 'no personal data\n' >clean.txt
  git add clean.txt
  run git commit -q -m clean
  [ "$status" -eq 0 ]
}
