# shellcheck disable=SC2016,SC2088 # literal $HOME and ~ are Mole's whitelist forms and inputs under test

setup() {
  load helpers
  HOME=$(realpath "$HOME")
  GUARD="$SCRIPTS_DIR/guard.sh"
  C="$HOME/Library/Containers"
  LIB="$HOME/Pictures/Photos Library.photoslibrary"
  WL="$HOME/.config/mole/whitelist"
  mkdir -p "$C" "$LIB/originals" "$HOME/Documents" "$HOME/tmp" "$HOME/.config/mole"
}

teardown() {
  chmod -R u+rwx "$HOME" 2>/dev/null || true
}

refused() { [ "$status" -eq 3 ] && [[ "$stderr" == *"refused: $1 (protected by "* ]]; }

# --- check ---------------------------------------------------------------

@test "check: exact protected path refused" {
  run_script "$GUARD" check "$C"
  refused "$C"
}

@test "check: path inside protected refused" {
  run_script "$GUARD" check "$C/com.x/Data/file"
  refused "$C/com.x/Data/file"
}

@test "check: photos library and its content refused" {
  run_script "$GUARD" check "$LIB"
  refused "$LIB"
  run_script "$GUARD" check "$LIB/originals"
  refused "$LIB/originals"
}

@test "check: symlink into protected refused" {
  mkdir -p "$C/com.x"
  ln -s "$C/com.x" "$HOME/tmp/link"
  run_script "$GUARD" check "$HOME/tmp/link"
  refused "$HOME/tmp/link"
}

@test "check: relative symlink chain into protected refused" {
  ln -s "../Pictures/Photos Library.photoslibrary" "$HOME/tmp/one"
  ln -s one "$HOME/tmp/two"
  run_script "$GUARD" check "$HOME/tmp/two"
  refused "$HOME/tmp/two"
}

@test "check: dangling symlink whose parent is protected refused" {
  ln -s "$C/gone/deeper" "$HOME/tmp/dangling"
  run_script "$GUARD" check "$HOME/tmp/dangling"
  refused "$HOME/tmp/dangling"
}

@test "check: symlink loop refused" {
  ln -s "$HOME/tmp/b" "$HOME/tmp/a"
  ln -s "$HOME/tmp/a" "$HOME/tmp/b"
  run_script "$GUARD" check "$HOME/tmp/a"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"refused: $HOME/tmp/a (symlink loop)"* ]]
  run_script "$GUARD" check "$HOME/tmp/a/x"
  [[ "$stderr" == *"refused: $HOME/tmp/a/x (symlink loop)"* ]]
}

@test "check: spaces, quotes and non-ASCII paths" {
  odd="it's \"q\" é ü"
  mkdir -p "$C/$odd"
  run_script "$GUARD" check "$C/$odd"
  refused "$C/$odd"
  run_script "$GUARD" check "$HOME/Documents/$odd"
  [ "$status" -eq 0 ]
}

@test "check: relative and empty paths refused" {
  run_script "$GUARD" check Library/Containers
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"refused: Library/Containers (relative path)"* ]]
  run_script "$GUARD" check ""
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"refused: '' (empty path)"* ]]
}

@test "check: root and home refused" {
  run_script "$GUARD" check /
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"refused: / (root)"* ]]
  run_script "$GUARD" check "$HOME"
  refused "$HOME"
  run_script "$GUARD" check "$HOME/"
  refused "$HOME/"
}

@test "check: parent of a protected path refused" {
  run_script "$GUARD" check "$HOME/Pictures"
  refused "$HOME/Pictures"
  run_script "$GUARD" check "$HOME/Library"
  refused "$HOME/Library"
  ln -s "$HOME/Pictures" "$HOME/tmp/pics"
  run_script "$GUARD" check "$HOME/tmp/pics"
  refused "$HOME/tmp/pics"
}

@test "check: other letter case of a protected path refused" {
  run_script "$GUARD" check "$HOME/LIBRARY/containers/com.x"
  refused "$HOME/LIBRARY/containers/com.x"
}

@test "check: .. inside a missing part is normalised" {
  run_script "$GUARD" check "$HOME/Documents/missing/./../../Library/Containers/x"
  refused "$HOME/Documents/missing/./../../Library/Containers/x"
}

@test "check: ~ in an argument expands to HOME" {
  run_script "$GUARD" check "~/Library/Containers"
  refused "~/Library/Containers"
}

@test "check: --allow-app allows only that app and its extensions" {
  run_script "$GUARD" check --allow-app com.example.app "$C/com.example.app" "$C/com.example.app.widget/Data" "$C/com.example.app/Data/x"
  [ "$status" -eq 0 ]
  run_script "$GUARD" check --allow-app com.example.app "$C/com.example.appx"
  refused "$C/com.example.appx"
  run_script "$GUARD" check --allow-app com.example.app "$C/com.other.app"
  refused "$C/com.other.app"
  run_script "$GUARD" check --allow-app com.example.app "$C"
  refused "$C"
}

@test "check: --allow-app keeps other protections" {
  run_script "$GUARD" check --allow-app com.example.app "$LIB"
  refused "$LIB"
  echo "$C/com.example.app/Data/keep" >"$WL"
  run_script "$GUARD" check --allow-app com.example.app "$C/com.example.app"
  refused "$C/com.example.app"
  run_script "$GUARD" check --allow-app com.example.app "$C/com.example.app/Data/keep/x"
  refused "$C/com.example.app/Data/keep/x"
}

@test "check: invalid --allow-app is a usage error" {
  for id in "" com ../x .com.x com.x. "com..x" "com.x/y" "com.*"; do
    run_script "$GUARD" check --allow-app "$id" "$HOME/tmp"
    [ "$status" -eq 2 ]
  done
  run_script "$GUARD" check --allow-app
  [ "$status" -eq 2 ]
}

@test "check: rules that cannot be resolved stay literal" {
  rm -rf "$C"
  ln -s "$C" "$C"
  ln -s "$HOME/tmp/a" "$HOME/tmp/a"
  printf '%s\n' "$HOME/tmp/a/x" "$HOME/tmp/a/*" >"$WL"
  run_script "$GUARD" check "$HOME/Documents/x"
  [ "$status" -eq 0 ]
  run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  [ "$(grep -c 'Library/Containers' "$WL")" = 1 ]
}

@test "check: unrelated paths allowed" {
  run_script "$GUARD" check "$HOME/Library/Caches/foo" "$HOME/tmp" /Applications/Nothing.app
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "check: every refused path is reported" {
  run_script "$GUARD" check "$HOME/tmp" "$C/a" "$LIB"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"refused: $C/a "* ]]
  [[ "$stderr" == *"refused: $LIB "* ]]
  [[ "$stderr" != *"refused: $HOME/tmp "* ]]
}

@test "check: whitelist lines with ~ and HOME forms protect" {
  printf '%s\n' '~/Keep1' '$HOME/Keep2' '${HOME}/Keep3' >"$WL"
  for n in 1 2 3; do
    run_script "$GUARD" check "$HOME/Keep$n/file"
    refused "$HOME/Keep$n/file"
  done
}

@test "check: whitelist comments, blanks, .., sentinel and relative lines ignored" {
  printf '%s\n' '# $HOME/Documents' '' '   ' '$HOME/Documents/../Documents' FINDER_METADATA 'Documents' >"$WL"
  run_script "$GUARD" check "$HOME/Documents/x"
  [ "$status" -eq 0 ]
}

@test "check: whitelist glob matches as prefix of its fixed part" {
  printf '%s\n' '$HOME/Library/Caches/JetBrains*' '$HOME/.gradle/caches/*' >"$WL"
  run_script "$GUARD" check "$HOME/Library/Caches/JetBrainsToolbox/x"
  refused "$HOME/Library/Caches/JetBrainsToolbox/x"
  run_script "$GUARD" check "$HOME/Library/Caches"
  refused "$HOME/Library/Caches"
  run_script "$GUARD" check "$HOME/.gradle/caches"
  refused "$HOME/.gradle/caches"
  run_script "$GUARD" check "$HOME/Library/Caches/Other" "$HOME/.gradle/wrapper"
  [ "$status" -eq 0 ]
}

@test "check: no whitelist file protects Mole's default list" {
  rm -f "$WL"
  run_script "$GUARD" check "$HOME/Library/Caches/example-tool/x"
  refused "$HOME/Library/Caches/example-tool/x"
  run_script "$GUARD" check "$HOME/Library/Caches/other"
  [ "$status" -eq 0 ]
}

@test "check: no whitelist file and no Mole lib exits 2" {
  rm -f "$WL"
  DISKDIET_MOLE_LIB='' run_script "$GUARD" check "$HOME/Documents/x"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"Mole"* ]]
}

@test "check: unreadable Pictures protects all of Pictures" {
  chmod 000 "$HOME/Pictures"
  run_script "$GUARD" check "$HOME/Pictures/any.jpg"
  refused "$HOME/Pictures/any.jpg"
  [[ "$stderr" == *"(unreadable)"* ]]
}

@test "usage errors exit 2" {
  run_script "$GUARD"
  [ "$status" -eq 2 ]
  run_script "$GUARD" check
  [ "$status" -eq 2 ]
  run_script "$GUARD" nope
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage:"* ]]
}

@test "missing jq exits 2" {
  status=0
  PATH=/nonexistent "$SCRIPT_BASH" "$GUARD" list 2>"$BATS_TEST_TMPDIR/stderr" || status=$?
  [ "$status" -eq 2 ]
  grep -q jq "$BATS_TEST_TMPDIR/stderr"
}

# --- whitelist -------------------------------------------------------------

@test "whitelist: new file seeded with Mole defaults, then built-ins" {
  rm -rf "$HOME/.config/mole"
  DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib" run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  expected=$(printf '%s\n' \
    '$HOME/Library/Caches/example-tool*' '$HOME/.example/models/*' '$HOME/Library/Application Support/JetBrains*' \
    '$HOME/Library/Mobile Documents*' FINDER_METADATA \
    '$HOME/Library/Containers' '$HOME/Pictures/Photos Library.photoslibrary')
  [ "$(cat "$WL")" = "$expected" ]
  [ "$output" = "$(jq -cn '["$HOME/Library/Containers","$HOME/Pictures/Photos Library.photoslibrary","disk_permissions_repair"]')" ]
}

@test "whitelist: resolved form added when HOME is a symlink" {
  real="$BATS_TEST_TMPDIR/realhome"
  mv "$HOME" "$real"
  ln -s "$real" "$HOME"
  DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib" run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  resolved=$(realpath "$real")
  grep -qxF '$HOME/Library/Containers' "$WL"
  grep -qxF "$resolved/Library/Containers" "$WL"
  grep -qxF "$resolved/Pictures/Photos Library.photoslibrary" "$WL"
  if grep -v -e example -e JetBrains -e 'Mobile Documents' "$WL" | grep -q '[*?]'; then false; fi
}

@test "whitelist: existing file kept, only missing lines added in order" {
  printf '%s\n' '# mine' '$HOME/Pictures/Photos Library.photoslibrary' '$HOME/Custom' >"$WL"
  run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  expected=$(printf '%s\n' '# mine' '$HOME/Pictures/Photos Library.photoslibrary' '$HOME/Custom' '$HOME/Library/Containers')
  [ "$(cat "$WL")" = "$expected" ]
  [ "$output" = '["$HOME/Library/Containers","disk_permissions_repair"]' ]
}

@test "whitelist: existing file without trailing newline" {
  printf '%s' '/keep/me' >"$WL"
  run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  [ "$(head -1 "$WL")" = /keep/me ]
  grep -qxF '$HOME/Library/Containers' "$WL"
}

@test "whitelist: idempotent" {
  DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib" run_script "$GUARD" whitelist
  before=$(cat "$WL" "$HOME/.config/mole/whitelist_optimize")
  DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib" run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
  [ "$(cat "$WL" "$HOME/.config/mole/whitelist_optimize")" = "$before" ]
}

@test "whitelist: interrupted write leaves the old file" {
  echo /keep/me >"$WL"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/mv"
  chmod +x "$BATS_TEST_TMPDIR/bin/mv"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$GUARD" whitelist
  [ "$status" -eq 2 ]
  [ "$(cat "$WL")" = /keep/me ]
  [ "$(find "$HOME/.config/mole" -type f | wc -l | tr -d ' ')" = 1 ]
}

@test "whitelist: unwritable config folder exits 2, never 1" {
  echo /keep/me >"$WL"
  chmod 555 "$HOME/.config/mole"
  run_script "$GUARD" whitelist
  chmod 755 "$HOME/.config/mole"
  [ "$status" -eq 2 ]
  [ "$(cat "$WL")" = /keep/me ]
}

@test "whitelist and check: a whitelist that is not a regular file exits 2" {
  rm -f "$WL"
  mkdir -p "$WL"
  run_script "$GUARD" whitelist
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"not a regular file"* ]]
  [ -z "$(ls -A "$WL")" ]
  run_script "$GUARD" check "$HOME/Downloads/x"
  [ "$status" -eq 2 ]
  rmdir "$WL"
  mkdir -p "$HOME/.config/mole/whitelist_optimize"
  run_script "$GUARD" whitelist
  [ "$status" -eq 2 ]
}

@test "check: unreadable whitelist exits 2, never 1" {
  echo /keep/me >"$WL"
  chmod 000 "$WL"
  run_script "$GUARD" check "$HOME/Downloads/x"
  chmod 644 "$WL"
  [ "$status" -eq 2 ]
}

@test "check: unsearchable config folder exits 2, never falls back to defaults" {
  echo '$HOME/Documents' >"$WL"
  chmod 000 "$HOME/.config/mole"
  run_script "$GUARD" check "$HOME/Documents"
  chmod 755 "$HOME/.config/mole"
  [ "$status" -eq 2 ]
  chmod 000 "$HOME/.config"
  run_script "$GUARD" check "$HOME/Documents"
  chmod 755 "$HOME/.config"
  [ "$status" -eq 2 ]
}

@test "check: unset or empty HOME exits 2" {
  env -u HOME "$SCRIPT_BASH" "$GUARD" check /tmp/x 2>/dev/null || status=$?
  [ "$status" -eq 2 ]
  HOME="" run_script "$GUARD" check /tmp/x
  [ "$status" -eq 2 ]
}

@test "check: /.nofollow alias of a protected path refused" {
  run_script "$GUARD" check "/.nofollow$C"
  [ "$status" -eq 3 ]
  ln -s "/.nofollow$C" "$HOME/tmp/nf"
  run_script "$GUARD" check "$HOME/tmp/nf"
  [ "$status" -eq 3 ]
}

@test "whitelist: unreadable Pictures exits 2 with the reason" {
  chmod 000 "$HOME/Pictures"
  DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib" run_script "$GUARD" whitelist
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"Pictures"*"not readable"* ]]
  [ ! -e "$WL" ]
}

@test "whitelist: Mole lib from the SCRIPT_DIR pinned in the launcher" {
  rm -f "$WL"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/pinned"
  cp -R "$FIXTURES_DIR/mole-lib" "$BATS_TEST_TMPDIR/pinned/lib"
  printf '#!/bin/bash\nSCRIPT_DIR="%s"\n' "$BATS_TEST_TMPDIR/pinned" >"$BATS_TEST_TMPDIR/bin/mo"
  chmod +x "$BATS_TEST_TMPDIR/bin/mo"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  grep -qxF 'FINDER_METADATA' "$WL"
}

@test "whitelist: Mole lib next to the resolved Homebrew symlink" {
  rm -f "$WL"
  cellar="$BATS_TEST_TMPDIR/brew/Cellar/mole/1/libexec"
  mkdir -p "$cellar" "$BATS_TEST_TMPDIR/brew/bin"
  cp -R "$FIXTURES_DIR/mole-lib" "$cellar/lib"
  printf '#!/bin/bash\nSCRIPT_DIR="$(dirname "$SCRIPT_PATH")"\n' >"$cellar/mole"
  chmod +x "$cellar/mole"
  ln -s ../Cellar/mole/1/libexec/mole "$BATS_TEST_TMPDIR/brew/bin/mo"
  PATH="$BATS_TEST_TMPDIR/brew/bin:$PATH" run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  grep -qxF 'FINDER_METADATA' "$WL"
}

@test "whitelist: Mole lib from ~/.config/mole/lib" {
  rm -f "$WL"
  cp -R "$FIXTURES_DIR/mole-lib" "$HOME/.config/mole/lib"
  run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  grep -qxF 'FINDER_METADATA' "$WL"
}

@test "whitelist: no mo on PATH still finds ~/.config/mole/lib" {
  rm -f "$WL"
  unset DISKDIET_MOLE_LIB
  cp -R "$FIXTURES_DIR/mole-lib" "$HOME/.config/mole/lib"
  PATH=/usr/bin:/bin run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  grep -qxF FINDER_METADATA "$WL"
}

@test "whitelist: no Mole lib found exits 2 and writes nothing" {
  rm -f "$WL"
  unset DISKDIET_MOLE_LIB
  run_script "$GUARD" whitelist
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"Mole"* ]]
  [ ! -e "$WL" ]
  [ ! -e "$HOME/.config/mole/whitelist_optimize" ]
}

@test "whitelist: unparsable Mole defaults exit 2 and write nothing" {
  rm -f "$WL"
  mkdir -p "$BATS_TEST_TMPDIR/bad/core"
  for body in 'nothing here' $'declare -a DEFAULT_WHITELIST_PATTERNS=(\n    "$(whoami)/x"\n)' $'declare -a DEFAULT_WHITELIST_PATTERNS=(\n)' $'declare -a DEFAULT_WHITELIST_PATTERNS=(\n    "$HOME/$USER/x"\n)'; do
    printf '%s\n' "$body" >"$BATS_TEST_TMPDIR/bad/core/base.sh"
    DISKDIET_MOLE_LIB="$BATS_TEST_TMPDIR/bad" run_script "$GUARD" whitelist
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"parse"* ]]
    [ ! -e "$WL" ]
  done
}

@test "whitelist: permissions reset excluded in a new whitelist_optimize" {
  DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib" run_script "$GUARD" whitelist
  [ "$(cat "$HOME/.config/mole/whitelist_optimize")" = disk_permissions_repair ]
}

@test "whitelist: optimize task excluded when a protected path holds its files" {
  printf '%s\n' '$HOME/Library/Messages' >"$WL"
  DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib" run_script "$GUARD" whitelist
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/mole/whitelist_optimize")" = "$(printf '%s\n' disk_permissions_repair sqlite_vacuum)" ]
  [[ "$output" == *'"sqlite_vacuum"'* ]]
}

@test "whitelist: optimize task excluded when a protected path lies inside its folder" {
  printf '%s\n' '~/Library/Preferences/com.example.app.plist' >"$WL"
  DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib" run_script "$GUARD" whitelist
  [ "$(cat "$HOME/.config/mole/whitelist_optimize")" = "$(printf '%s\n' disk_permissions_repair fix_broken_configs)" ]
}

@test "whitelist: whitelist_optimize seeded from legacy whitelist_checks" {
  printf '%s\n' '# old' maintenance_scripts >"$HOME/.config/mole/whitelist_checks"
  DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib" run_script "$GUARD" whitelist
  [ "$(cat "$HOME/.config/mole/whitelist_optimize")" = "$(printf '%s\n' '# old' maintenance_scripts disk_permissions_repair)" ]
}

@test "whitelist: existing whitelist_optimize kept, task added once" {
  printf '%s\n' spotlight_rebuild >"$HOME/.config/mole/whitelist_optimize"
  printf '%s\n' ignored_legacy >"$HOME/.config/mole/whitelist_checks"
  DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib" run_script "$GUARD" whitelist
  [ "$(cat "$HOME/.config/mole/whitelist_optimize")" = "$(printf '%s\n' spotlight_rebuild disk_permissions_repair)" ]
}

# --- list --------------------------------------------------------------------

@test "list: built-ins only when no whitelist" {
  run_script "$GUARD" list
  [ "$status" -eq 0 ]
  home=$(realpath "$HOME")
  [ "$output" = "$(jq -cn --arg c "$home/Library/Containers" --arg l "$home/Pictures/Photos Library.photoslibrary" '[$c,$l]')" ]
}

@test "list: whitelist concrete paths resolved, globs, sentinel and comments skipped" {
  printf '%s\n' '# c' '$HOME/Keep' '~/Library/Caches/JetBrains*' FINDER_METADATA '$HOME/a/../b' '$HOME/Library/Containers' >"$WL"
  run_script "$GUARD" list
  [ "$status" -eq 0 ]
  home=$(realpath "$HOME")
  [ "$output" = "$(jq -cn --arg c "$home/Library/Containers" --arg l "$home/Pictures/Photos Library.photoslibrary" --arg k "$home/Keep" '[$c,$l,$k]')" ]
}

@test "list: no Pictures folder" {
  rm -rf "$HOME/Pictures"
  run_script "$GUARD" list
  [ "$output" = "$(jq -cn --arg c "$C" '[$c]')" ]
}

@test "list: unreadable Pictures listed whole" {
  chmod 000 "$HOME/Pictures"
  run_script "$GUARD" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(realpath "$HOME")/Pictures\""* ]]
}

# --- uninstall-check ---------------------------------------------------------

@test "uninstall-check: preview of only the picked app's paths passes" {
  run_script "$GUARD" uninstall-check --allow-app com.example.app <"$FIXTURES_DIR/mo_uninstall_dry_run.txt"
  [ "$status" -eq 0 ]
}

@test "uninstall-check: protected paths in the preview refused" {
  input="$BATS_TEST_TMPDIR/in.txt"
  cp "$FIXTURES_DIR/mo_uninstall_dry_run.txt" "$input"
  printf '  \033[0;32m✓\033[0m ~/Pictures/Photos Library.photoslibrary \033[0;90m, 2.00GB\033[0m\n' >>"$input"
  printf '  \033[0;34m◎\033[0m System: ~/Library/Containers/com.other.app\n' >>"$input"
  run_script "$GUARD" uninstall-check --allow-app com.example.app <"$input"
  refused "$LIB"
  [[ "$stderr" == *"refused: $C/com.other.app (protected by"* ]]
  [[ "$stderr" != *"refused: $C/com.example.app"* ]]
}

@test "uninstall-check: CRLF preview still refuses protected paths" {
  printf '  ✓ ~/Pictures/Photos Library.photoslibrary\r\n  ✓ ~/Library/Containers , 1.00GB\r\n' >"$BATS_TEST_TMPDIR/in.txt"
  run_script "$GUARD" uninstall-check --allow-app com.example.app --preview "$BATS_TEST_TMPDIR/in.txt"
  refused "$LIB"
  refused "$C"
}

@test "uninstall-check: a path too long to resolve never passes" {
  { printf '  ✓ ~/Library/Caches/'; head -c 1100000 /dev/zero | tr '\0' a; echo; } >"$BATS_TEST_TMPDIR/in.txt"
  run_script "$GUARD" uninstall-check --allow-app com.example.app --preview "$BATS_TEST_TMPDIR/in.txt"
  [ "$status" -ne 0 ]
}

@test "uninstall-check: Homebrew cask refused, its zap paths are not in the preview" {
  input="$BATS_TEST_TMPDIR/in.txt"
  sed $'1s/Example App/Example App \033[0;36m[Brew]\033[0m/' "$FIXTURES_DIR/mo_uninstall_dry_run.txt" >"$input"
  grep -q '\[Brew\]' "$input"
  run_script "$GUARD" uninstall-check --allow-app com.example.app <"$input"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"refused: Homebrew cask"* ]]
}

@test "uninstall-check: --shown passes when the new preview lists only shown paths" {
  input="$BATS_TEST_TMPDIR/in.txt"
  sed 's/12\.3MB/12.9MB/' "$FIXTURES_DIR/mo_uninstall_dry_run.txt" | grep -v widget >"$input"
  run_script "$GUARD" uninstall-check --allow-app com.example.app --shown "$FIXTURES_DIR/mo_uninstall_dry_run.txt" <"$input"
  [ "$status" -eq 0 ]
}

@test "uninstall-check: --shown refuses a path the shown preview lacked" {
  input="$BATS_TEST_TMPDIR/in.txt"
  cp "$FIXTURES_DIR/mo_uninstall_dry_run.txt" "$input"
  printf '  \033[0;32m✓\033[0m ~/Library/Caches/com.example.app \033[0;90m, 1.0MB\033[0m\n' >>"$input"
  run_script "$GUARD" uninstall-check --allow-app com.example.app --shown "$FIXTURES_DIR/mo_uninstall_dry_run.txt" <"$input"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"refused: $HOME/Library/Caches/com.example.app (not in the preview shown)"* ]]
}

@test "uninstall-check: --shown file unreadable or without paths exits 2" {
  run_script "$GUARD" uninstall-check --allow-app com.example.app --shown "$BATS_TEST_TMPDIR/missing" <"$FIXTURES_DIR/mo_uninstall_dry_run.txt"
  [ "$status" -eq 2 ]
  printf 'No apps selected\n' >"$BATS_TEST_TMPDIR/empty.txt"
  run_script "$GUARD" uninstall-check --allow-app com.example.app --shown "$BATS_TEST_TMPDIR/empty.txt" <"$FIXTURES_DIR/mo_uninstall_dry_run.txt"
  [ "$status" -eq 2 ]
}

@test "uninstall-check: --preview reads the preview from a file" {
  run_script "$GUARD" uninstall-check --allow-app com.example.app --preview "$FIXTURES_DIR/mo_uninstall_dry_run.txt" </dev/null
  [ "$status" -eq 0 ]
  input="$BATS_TEST_TMPDIR/in.txt"
  cp "$FIXTURES_DIR/mo_uninstall_dry_run.txt" "$input"
  printf '  ~/Library/Caches/com.example.app\n' >>"$input"
  run_script "$GUARD" uninstall-check --allow-app com.example.app --shown "$FIXTURES_DIR/mo_uninstall_dry_run.txt" --preview "$input" </dev/null
  [ "$status" -eq 3 ]
  run_script "$GUARD" uninstall-check --allow-app com.example.app --preview "$BATS_TEST_TMPDIR/missing" </dev/null
  [ "$status" -eq 2 ]
}

@test "uninstall-check: unparsable input exits 2" {
  run_script "$GUARD" uninstall-check --allow-app com.example.app <<<"No apps selected"
  [ "$status" -eq 2 ]
  run_script "$GUARD" uninstall-check --allow-app com.example.app </dev/null
  [ "$status" -eq 2 ]
}

@test "uninstall-check: --allow-app required" {
  run_script "$GUARD" uninstall-check <"$FIXTURES_DIR/mo_uninstall_dry_run.txt"
  [ "$status" -eq 2 ]
  run_script "$GUARD" uninstall-check --allow-app com <"$FIXTURES_DIR/mo_uninstall_dry_run.txt"
  [ "$status" -eq 2 ]
  run_script "$GUARD" uninstall-check --app com.example.app <"$FIXTURES_DIR/mo_uninstall_dry_run.txt"
  [ "$status" -eq 2 ]
  run_script "$GUARD" uninstall-check --allow-app com.example.app --seen x <"$FIXTURES_DIR/mo_uninstall_dry_run.txt"
  [ "$status" -eq 2 ]
}
