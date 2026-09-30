setup() {
  load helpers
  HOME=$(realpath "$HOME")
  export CLAUDE_SKILL_DIR="$TESTS_DIR/../skills/diskdiet"
  export TMPDIR="$BATS_TEST_TMPDIR/t" FREE_GB=80 SWAP_GB=1 CACHES_GB=unknown
  mkdir -p "$TMPDIR"
  RUN=$(mktemp -d "$TMPDIR/diskdiet-XXXXXX")
  export RUN
  seed_home
}

# seed_home: user files the analyse stage must leave alone.
seed_home() {
  mkdir -p "$HOME/Pictures/Photos Library.photoslibrary/resources" \
    "$HOME/Library/Containers/com.example.app/Data" \
    "$HOME/Library/Caches/com.example.junk" \
    "$HOME/Projects/app/node_modules/x" "$HOME/Documents"
  echo photo >"$HOME/Pictures/Photos Library.photoslibrary/resources/a.jpg"
  echo data >"$HOME/Library/Containers/com.example.app/Data/prefs"
  head -c 200000 /dev/urandom >"$HOME/Library/Caches/com.example.junk/blob"
  echo '{}' >"$HOME/Projects/app/package.json"
  echo module >"$HOME/Projects/app/node_modules/x/index.js"
  echo note >"$HOME/Documents/note.txt"
  find "$HOME" -exec touch -t 202501010000 {} +
  (cd "$HOME" && find . -type f -exec shasum {} + | sort) >"$BATS_TEST_TMPDIR/seeded"
}

# unchanged: every seeded file still exists with the same content.
unchanged() { (cd "$HOME" && shasum -c --quiet "$BATS_TEST_TMPDIR/seeded"); }

# run_analyse: every command line of analyse.cmds, in order.
run_analyse() {
  local line
  while IFS= read -r line; do
    case $line in "" | "#"*) continue ;; esac
    eval "$line" >>"$BATS_TEST_TMPDIR/analyse.out" 2>&1 || {
      echo "failed: $line" >&2
      return 1
    }
  done <"$CLAUDE_SKILL_DIR/scripts/analyse.cmds"
}

# new_paths: paths under HOME that were not seeded.
new_paths() { comm -13 <(sed 's/^[0-9a-f]*  //' "$BATS_TEST_TMPDIR/seeded" | sort) <(cd "$HOME" && find . -type f | sort); }

@test "analyse commands with stubs change no file and call no removing command" {
  healthy
  stub_output mo mo_version.txt --version
  stub_output mo mo_analyze.json analyze --json "$HOME"
  stub_output mo mo_clean_dry_run.txt clean --dry-run
  stub_output diskutil diskutil_apfs_snapshots_data.txt apfs list
  run_analyse
  unchanged
  [ -z "$(new_paths)" ]
  grep -q '^mo analyze --json ' "$STUB_LOG"
  grep -q '^mo clean --dry-run$' "$STUB_LOG"
  grep -q '^tmutil listlocalsnapshots /$' "$STUB_LOG"
  removing=$(grep -E '^(mo (clean|purge|uninstall|optimize)|tmutil (delete|thin)|rm )' "$STUB_LOG" | grep -v -- '--dry-run' || true)
  [ -z "$removing" ]
  /usr/bin/jq -e '.free_gb' "$RUN/before.json"
  /usr/bin/jq -e '.target_gb' "$RUN/target.json"
}

@test "analyse commands with real Mole change no seeded file" {
  real_mo=$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin command -v mo) || skip "Mole not installed"
  PATH="$(dirname "$real_mo"):/usr/bin:/bin:/usr/sbin:/sbin"
  unset ANDROID_HOME ANDROID_SDK_ROOT
  run_analyse
  unchanged
  new=$(new_paths | grep -Ev '^\./(\.cache/mole|\.config/mole|Library/Logs/mole|Library/Caches|\.npm)/' || true)
  [ -z "$new" ]
  grep -q 'Library/Caches/com.example.junk' "$HOME/.config/mole/clean-list.txt"
}
