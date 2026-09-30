# Real Mole dry runs on a seeded temp HOME after `guard.sh whitelist`: nothing
# protected may show up in what Mole would remove (SC-003). Mole runs once per
# file; the tests read its output.

setup_file() {
  real_mo=$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin command -v mo) || return 0
  export REAL_MO=$real_mo
  export HOME="$BATS_FILE_TMPDIR/home" OUT="$BATS_FILE_TMPDIR/out"
  PATH="$(dirname "$real_mo"):/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH
  export MOLE_TEST_TRASH_DIR="$BATS_FILE_TMPDIR/trash"
  unset ANDROID_HOME ANDROID_SDK_ROOT
  mkdir -p "$HOME" "$OUT"
  HOME=$(realpath "$HOME")
  seed
  GUARD="$BATS_TEST_DIRNAME/../skills/diskdiet/scripts/guard.sh"
  "$GUARD" whitelist >"$OUT/whitelist.json"
  mo clean --dry-run </dev/null >"$OUT/clean.txt" 2>&1
  mo purge --dry-run </dev/null >"$OUT/purge.txt" 2>&1
  mo optimize --dry-run </dev/null >"$OUT/optimize.txt" 2>&1
  printf 'y\n' | mo uninstall --dry-run FakeTool >"$OUT/uninstall_jetbrains.txt" 2>&1
  printf 'y\n' | mo uninstall --dry-run Fake2 >"$OUT/uninstall_plain.txt" 2>&1
}

# fake_app <name> <bundle id>: a minimal app in ~/Applications.
fake_app() {
  local contents="$HOME/Applications/$1.app/Contents"
  mkdir -p "$contents/MacOS"
  printf '#!/bin/sh\n' >"$contents/MacOS/$1"
  chmod +x "$contents/MacOS/$1"
  cat >"$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleName</key><string>$1</string>
<key>CFBundleExecutable</key><string>$1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
</dict></plist>
EOF
}

seed() {
  local lib
  for lib in "Photos Library" "Old Photos"; do
    mkdir -p "$HOME/Pictures/$lib.photoslibrary/resources/caches/com.apple.photos"
    head -c 100000 /dev/urandom >"$HOME/Pictures/$lib.photoslibrary/resources/caches/com.apple.photos/blob"
  done
  mkdir -p "$HOME/Library/Containers/com.example.app/Data/Library/Caches/com.example.app" \
    "$HOME/Library/Mobile Documents/x" "$HOME/Library/Caches/com.example.junk"
  head -c 100000 /dev/urandom >"$HOME/Library/Containers/com.example.app/Data/Library/Caches/com.example.app/blob"
  head -c 100000 /dev/urandom >"$HOME/Library/Mobile Documents/x/doc"
  head -c 200000 /dev/urandom >"$HOME/Library/Caches/com.example.junk/blob"
  ln -s "$HOME/Pictures/Photos Library.photoslibrary/resources/caches" "$HOME/Library/Caches/x"
  mkdir -p "$HOME/Projects/app/node_modules/x"
  echo '{}' >"$HOME/Projects/app/package.json"
  head -c 100000 /dev/urandom >"$HOME/Projects/app/node_modules/x/blob"
  fake_app FakeTool com.jetbrains.toolbox
  mkdir -p "$HOME/Library/Application Support/JetBrains/Toolbox" "$HOME/Library/Caches/JetBrains/Toolbox" \
    "$HOME/Library/Containers/com.jetbrains.toolbox/Data"
  fake_app Fake2 com.example.fake2
  mkdir -p "$HOME/Library/Containers/com.example.fake2/Data" "$HOME/Library/Application Support/Fake2"
  find "$HOME" -exec touch -h -t 202501010000 {} +
}

setup() {
  [ -n "${REAL_MO:-}" ] || skip "Mole not installed"
  GUARD="$BATS_TEST_DIRNAME/../skills/diskdiet/scripts/guard.sh"
}

strip() { sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g' "$1"; }

# clean_paths: every path in Mole's clean list (clean prints only summaries).
clean_paths() { grep '^/' "$HOME/.config/mole/clean-list.txt" | sed 's/  # [^#]*$//'; }

purge_paths() { strip "$OUT/purge.txt" | sed -n 's/.*\[DRY RUN\] \(.*\), [0-9.]*[KMGT]*B$/\1/p' | sed "s|^~|$HOME|"; }

# check_resolved <path>...: guard.sh check on each path's physical location.
# A listed symlink is skipped: Mole removes the link alone with plain `rm`
# (lib/core/file_ops.sh:1777-1835), proven by the symlink test below.
check_resolved() {
  local p
  for p in "$@"; do
    [ -L "$p" ] && continue
    "$GUARD" check "$(realpath "$p" 2>/dev/null || echo "$p")" || return 1
  done
}

@test "clean dry run lists the unprotected cache (positive control)" {
  clean_paths | grep -q "^$HOME/Library/Caches/com.example.junk$"
}

@test "clean dry run lists no protected path, symlinks resolved" {
  local paths=()
  while IFS= read -r p; do paths+=("$p"); done <<<"$(clean_paths)"
  [ "${#paths[@]}" -gt 0 ]
  check_resolved "${paths[@]}"
}

@test "a listed symlink into a library is removed as a link, the library kept" {
  clean_paths | grep -q "^$HOME/Library/Caches/x$"
  local lib="$HOME/Pictures/Photos Library.photoslibrary/resources/caches/com.apple.photos/blob" before
  before=$(shasum "$lib")
  mole_lib="$(dirname "$(realpath "$REAL_MO")")/lib"
  cp -a "$HOME/Library/Caches/x" "$BATS_TEST_TMPDIR/x"
  bash -c 'source "$1/core/common.sh" && safe_remove "$2"' _ "$mole_lib" "$HOME/Library/Caches/x"
  [ ! -L "$HOME/Library/Caches/x" ]
  [ "$(shasum "$lib")" = "$before" ]
  cp -a "$BATS_TEST_TMPDIR/x" "$HOME/Library/Caches/x"
}

@test "purge dry run lists no protected path" {
  local paths=() p
  while IFS= read -r p; do [ -n "$p" ] && paths+=("$p"); done <<<"$(purge_paths)"
  printf '%s\n' "${paths[@]}" | grep -q "^$HOME/Projects/app/node_modules$"
  check_resolved "${paths[@]}"
}

@test "optimize dry run skips the permissions repair" {
  strip "$OUT/optimize.txt" | grep -q 'Skipped (whitelisted): Permission Repair'
}

@test "guard.sh names every Mole optimize task in its optimize table" {
  mole_tasks=$(bash -c 'source "$1/lib/optimize/catalog.sh"; printf "%s\n" "${MOLE_OPTIMIZE_ACTIONS[@]}"' _ "$(dirname "$(realpath "$REAL_MO")")" | sort -u)
  guard_tasks=$(sed -n "/<<'TASKS'/,/^TASKS/p" "$GUARD" | sed '1d;$d' | cut -d'|' -f1 | sort -u)
  [ -n "$mole_tasks" ]
  [ "$mole_tasks" = "$guard_tasks" ]
}

@test "optimize dry run skips a task whose files are protected" {
  local home2="$BATS_TEST_TMPDIR/home2"
  mkdir -p "$home2/.config/mole" "$home2/Library/Messages"
  # shellcheck disable=SC2016 # Mole's literal $HOME form
  printf '%s\n' '$HOME/Library/Messages' >"$home2/.config/mole/whitelist"
  HOME=$home2 "$GUARD" whitelist
  HOME=$home2 mo optimize --dry-run </dev/null >"$BATS_TEST_TMPDIR/optimize.txt" 2>&1
  strip "$BATS_TEST_TMPDIR/optimize.txt" | grep -q 'Skipped (whitelisted): Database Optimization'
}

@test "uninstall preview of a plain app holds only its own containers" {
  strip "$OUT/uninstall_plain.txt" | grep -q 'Library/Containers/com.example.fake2'
  "$GUARD" uninstall-check --allow-app com.example.fake2 <"$OUT/uninstall_plain.txt"
}

@test "uninstall preview hitting a Mole default whitelist entry is refused" {
  run "$GUARD" uninstall-check --allow-app com.jetbrains.toolbox <"$OUT/uninstall_jetbrains.txt"
  [ "$status" -eq 3 ]
  [[ "$output" == *"JetBrains/Toolbox"* ]]
}

@test "dry runs left every protected file in place" {
  [ -f "$HOME/Pictures/Photos Library.photoslibrary/resources/caches/com.apple.photos/blob" ]
  [ -f "$HOME/Pictures/Old Photos.photoslibrary/resources/caches/com.apple.photos/blob" ]
  [ -f "$HOME/Library/Containers/com.example.app/Data/Library/Caches/com.example.app/blob" ]
  [ -f "$HOME/Library/Mobile Documents/x/doc" ]
  [ -d "$HOME/Applications/FakeTool.app" ]
}
