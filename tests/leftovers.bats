setup() {
  load helpers
  LEFTOVERS="$SCRIPTS_DIR/leftovers.sh"
  export DISKDIET_CLAUDE_TMP="$BATS_TEST_TMPDIR/claude-tmp"
  export TMPDIR="$BATS_TEST_TMPDIR/folders/T/"
  mkdir -p "$TMPDIR" "$BATS_TEST_TMPDIR/folders/X"
}

NL=$'\n'

field() { printf '%s' "$output" | /usr/bin/jq -c "$1"; }

# repo_with_worktree <name>: ~/Projects/<name> with one commit on main and a
# linked worktree <name>-wt on branch wt, all dated 2020.
repo_with_worktree() {
  local r="$HOME/Projects/$1"
  git init -q -b main "$r"
  git -C "$r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git -C "$r" worktree add -q "$r-wt" -b wt
  find "$r-wt" -exec touch -h -t 202001010000 {} +
}

wt_commit() { git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$2"; }

# unit <path> [old]: a folder holding one 2 KB file; "old" dates it to 2020.
unit() {
  mkdir -p "$1"
  head -c 2048 /dev/zero >"$1/data"
  if [ "${2:-}" = old ]; then find "$1" -exec touch -t 202001010000 {} +; fi
}

@test "leftovers: nothing found lists no items and measures restart space" {
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field .items)" = '[]' ]
  [ "$(field '.restart_gb | type')" = '"number"' ]
  [ "$(field .simulator_runtimes)" = null ]
}

@test "leftovers: list groups every catalog path by id with its units" {
  unit "$HOME/.android/avd/Pixel.avd" old
  unit "$HOME/.android/avd/Tablet.avd" old
  unit "$HOME/.gradle/caches" old
  unit "$HOME/Library/Android/sdk/system-images/android-34" old
  unit "$HOME/Library/Developer/Xcode/iOS DeviceSupport/18.0" old
  unit "$HOME/Library/Caches/ms-playwright/chromium-1" old
  unit "$HOME/.lmstudio/models/lmstudio-community/qwen" old
  unit "$HOME/Library/Application Support/Claude/vm_bundles" old
  unit "$DISKDIET_CLAUDE_TMP/-Users-x-old" old
  unit "$HOME/.cache/uv" old
  unit "$HOME/Library/Developer/Xcode/DerivedData/App-abc" old
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '["android-avd","android-system-images","claude-tmp","claude-vm-bundles","gradle-caches","lm-studio-models","playwright","uv-cache","xcode-derived-data","xcode-device-support"]' ]
  [ "$(field '[.items[] | select(.id == "android-avd") | .units[].path | sub(".*/"; "")]')" = '["Pixel.avd","Tablet.avd"]' ]
  [ "$(field '[.items[].units[] | .in_use, .protected] | unique')" = '[null,false]' ]
}

@test "leftovers: an item lists its 10 biggest units and counts them all" {
  local n
  for n in 01 02 03 04 05 06 07 08 09 10 11; do unit "$DISKDIET_CLAUDE_TMP/s$n" old; done
  head -c 65536 /dev/zero >"$DISKDIET_CLAUDE_TMP/s11/big"
  touch -t 202001010000 "$DISKDIET_CLAUDE_TMP/s11/big" "$DISKDIET_CLAUDE_TMP/s11"
  unit "$DISKDIET_CLAUDE_TMP/live"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '.items[0] | [.count, .in_use, .protected, (.units | length)]')" = '[12,1,0,10]' ]
  [ "$(field '.items[0].units[0].path | sub(".*/"; "")')" = '"s11"' ]
}

@test "leftovers: a path changed in the last 120 minutes is in use" {
  unit "$DISKDIET_CLAUDE_TMP/-Users-x-old" old
  unit "$DISKDIET_CLAUDE_TMP/-Users-x-live"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[0].units[] | [(.path | sub(".*/"; "")), .in_use]]')" = '[["-Users-x-old",false],["-Users-x-live",true]]' ]
}

@test "leftovers: a claude temp folder that is a symlink or not ours is skipped" {
  mkdir -p "$BATS_TEST_TMPDIR/home-data"
  unit "$BATS_TEST_TMPDIR/home-data/keep" old
  ln -s "$BATS_TEST_TMPDIR/home-data" "$DISKDIET_CLAUDE_TMP"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field .items)" = '[]' ]
  run_script "$LEFTOVERS" remove claude-tmp
  [ "$status" -eq 0 ]
  [ -e "$BATS_TEST_TMPDIR/home-data/keep/data" ]
  DISKDIET_CLAUDE_TMP=/ run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field .items)" = '[]' ]
}

@test "leftovers: a dangling symlink is still a unit" {
  mkdir -p "$HOME/.android/avd"
  ln -s "$BATS_TEST_TMPDIR/missing" "$HOME/.android/avd/gone.avd"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[0].units[].path | sub(".*/"; "")]')" = '["gone.avd"]' ]
}

@test "leftovers: a path with a newline in its name is never a unit" {
  mkdir -p "$HOME/.config/mole"
  printf '%s\n' "\$HOME/keep" >"$HOME/.config/mole/whitelist"
  unit "$HOME/keep" old
  mkdir -p "$HOME/.android/avd/a${NL}b"
  ln -s "$HOME/keep/data" "$HOME/.android/avd/a${NL}b/data"
  run_script "$LEFTOVERS" remove android-avd
  [ "$status" -eq 0 ]
  [ -e "$HOME/keep/data" ]
  [ "$(field .removed)" = '[]' ]
}

@test "leftovers: a whitelisted path is marked protected" {
  mkdir -p "$HOME/.config/mole"
  printf '%s\n' "\$HOME/.gradle/caches/*" >"$HOME/.config/mole/whitelist"
  unit "$HOME/.gradle/caches" old
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  field '.items[0].units[0].protected' | grep -qF "\"refused: $HOME/.gradle/caches (protected by $HOME/.gradle/caches/*)\""
}

@test "leftovers: size comes from du, summed over removable units only, not measured in use" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -s "$TESTS_DIR/stubs/_stub" "$BATS_TEST_TMPDIR/bin/du"
  stub_output du du_1gb.txt
  unit "$HOME/.android/avd/Pixel.avd" old
  unit "$HOME/.android/avd/Tablet.avd"
  # One du for every unit not in use.
  printf '1048576\t%s\n' "$HOME/.android/avd/Pixel.avd" >"$BATS_TEST_TMPDIR/du.txt"
  export "STUB_DU_SKL_$(printf '%s' "$HOME/.android/avd/Pixel.avd" | tr '[:lower:]' '[:upper:]' | tr -cs 'A-Z0-9' '_' | sed 's/^_*//; s/_*$//')=$BATS_TEST_TMPDIR/du.txt"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '.items[0].gb')" = 1 ]
  [ "$(field '[.items[0].units[].gb]')" = '[1,null]' ]
  [ "$(field .restart_gb)" = 2 ]
}

@test "leftovers: a size du cannot measure is null and not counted" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -s "$TESTS_DIR/stubs/_stub" "$BATS_TEST_TMPDIR/bin/du"
  unit "$HOME/.android/avd/Pixel.avd" old
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '.items[0].units[0].gb')" = null ]
  [ "$(field '.items[0].gb')" = 0 ]
  [ "$(field .restart_gb)" = null ]
}

@test "leftovers: simulator runtimes preview comes from simctl's dry run, sized from its list" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_runtime_dry_run.txt simctl runtime delete --notUsedSinceDays 30 --dry-run
  stub_output xcrun simctl_runtime_list.json simctl runtime list -j
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field .simulator_runtimes)" = '["Would delete P: 00000000-0000-0000-0000-000000000000 iOS (26.5 - 23F77) (Ready)"]' ]
  [ "$(field .simulator_runtimes_gb)" = 8 ]
}

@test "leftovers: a runtime list simctl cannot give leaves runtime size unknown" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_runtime_dry_run.txt simctl runtime delete --notUsedSinceDays 30 --dry-run
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '.simulator_runtimes | length')" = 1 ]
  [ "$(field .simulator_runtimes_gb)" = null ]
}

@test "leftovers: without developer tools xcrun is never called" {
  stub_output xcrun simctl_runtime_dry_run.txt simctl runtime delete --notUsedSinceDays 30 --dry-run
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field .simulator_runtimes)" = null ]
  [ "$(field .simulator_devices)" = null ]
  [ "$(grep -c '^xcrun ' "$STUB_LOG")" = 0 ]
}

@test "leftovers: no TMPDIR leaves restart space unknown" {
  unset TMPDIR
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field .restart_gb)" = null ]
}

@test "leftovers: remove deletes old units, skips in-use and protected ones" {
  mkdir -p "$HOME/.config/mole"
  printf '%s\n' "\$HOME/.gradle/caches/*" >"$HOME/.config/mole/whitelist"
  unit "$DISKDIET_CLAUDE_TMP/-Users-x-old" old
  unit "$DISKDIET_CLAUDE_TMP/-Users-x-live"
  unit "$HOME/.gradle/caches" old
  run_script "$LEFTOVERS" remove claude-tmp gradle-caches
  [ "$status" -eq 0 ]
  [ ! -e "$DISKDIET_CLAUDE_TMP/-Users-x-old" ]
  [ -e "$DISKDIET_CLAUDE_TMP/-Users-x-live" ]
  [ -e "$HOME/.gradle/caches/data" ]
  [ "$(field '[.removed[] | sub(".*/"; "")]')" = '["-Users-x-old"]' ]
  [ "$(field '[.skipped[].reason | sub(" .*"; "")]')" = '["in","refused:"]' ]
  [ "$(field '.skipped[1].reason')" = "\"refused: $HOME/.gradle/caches (protected by $HOME/.gradle/caches/*)\"" ]
  [ "$(field .errors)" = '[]' ]
}

@test "leftovers: remove never follows a symlink into a protected place" {
  unit "$HOME/Library/Containers/com.example.App" old
  mkdir -p "$HOME/.android/avd"
  ln -s "$HOME/Library/Containers" "$HOME/.android/avd/evil.avd"
  run_script "$LEFTOVERS" remove android-avd
  [ "$status" -eq 0 ]
  [ -e "$HOME/Library/Containers/com.example.App/data" ]
  [ -L "$HOME/.android/avd/evil.avd" ]
  field '.skipped[0].reason' | grep -qF 'Library/Containers'
}

@test "leftovers: a guard that cannot check skips the unit" {
  unset DISKDIET_MOLE_LIB
  unit "$HOME/.android/avd/Pixel.avd" old
  PATH="/usr/bin:/bin" run_script "$LEFTOVERS" remove android-avd
  [ "$status" -eq 0 ]
  [ -e "$HOME/.android/avd/Pixel.avd/data" ]
  field '.skipped[0].reason' | grep -qF 'could not check'
  [ "$(field '.skipped[0].reason | test("\n")')" = false ]
}

@test "leftovers: a failed removal is reported as an error" {
  unit "$HOME/.android/avd/Pixel.avd" old
  chmod 500 "$HOME/.android/avd/Pixel.avd"
  run_script "$LEFTOVERS" remove android-avd
  chmod 700 "$HOME/.android/avd/Pixel.avd"
  [ "$status" -eq 0 ]
  [ "$(field .removed)" = '[]' ]
  field '.errors[0]' | grep -qF 'Pixel.avd'
}

@test "leftovers: simulator runtimes are removed by simctl, not rm" {
  stub_output xcode-select xcode_select_p.txt -p
  export STUB_XCRUN=/dev/null
  run_script "$LEFTOVERS" remove simulator-runtimes
  [ "$status" -eq 0 ]
  grep -qxF 'xcrun simctl runtime delete --notUsedSinceDays 30' "$STUB_LOG"
  [ "$(field .removed)" = '["simulator-runtimes"]' ]
}

@test "leftovers: a failing simctl is reported as an error" {
  stub_output xcode-select xcode_select_p.txt -p
  run_script "$LEFTOVERS" remove simulator-runtimes
  [ "$status" -eq 0 ]
  [ "$(field .removed)" = '[]' ]
  field '.errors[0]' | grep -qF 'simulator-runtimes'
}

@test "leftovers: no old simulator runtime is not an error" {
  stub_output xcode-select xcode_select_p.txt -p
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "No matching images found to delete" >&2\nexit 2\n' >"$BATS_TEST_TMPDIR/bin/xcrun"
  chmod +x "$BATS_TEST_TMPDIR/bin/xcrun"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$LEFTOVERS" remove simulator-runtimes
  [ "$status" -eq 0 ]
  [ "$(field .removed)" = '[]' ]
  [ "$(field .errors)" = '[]' ]
}

@test "leftovers: without developer tools remove never calls xcrun" {
  run_script "$LEFTOVERS" remove simulator-runtimes
  [ "$status" -eq 0 ]
  [ "$(grep -c '^xcrun ' "$STUB_LOG")" = 0 ]
  field '.errors[0]' | grep -qF 'developer tools are not installed'
}

@test "leftovers: a glob character, backslash or newline in HOME or the claude temp folder exits 2" {
  unit "$BATS_TEST_TMPDIR/h1/.gradle/caches" old
  unit "$BATS_TEST_TMPDIR/c1/session" old
  unit "$BATS_TEST_TMPDIR/victim/keep" old
  mkdir -p "$BATS_TEST_TMPDIR/h?" "$BATS_TEST_TMPDIR/c?" "$BATS_TEST_TMPDIR/h\1"
  HOME="$BATS_TEST_TMPDIR/h?" run_script "$LEFTOVERS" remove gradle-caches
  [ "$status" -eq 2 ]
  HOME="$BATS_TEST_TMPDIR/h\1" run_script "$LEFTOVERS" remove gradle-caches
  [ "$status" -eq 2 ]
  DISKDIET_CLAUDE_TMP="$BATS_TEST_TMPDIR/c?" run_script "$LEFTOVERS" remove claude-tmp
  [ "$status" -eq 2 ]
  HOME="$BATS_TEST_TMPDIR/hn${NL}android-avd|$BATS_TEST_TMPDIR/victim/*${NL}x" run_script "$LEFTOVERS" remove android-avd
  [ "$status" -eq 2 ]
  grep -qF 'unsupported characters' <<<"$stderr"
  [ -e "$BATS_TEST_TMPDIR/h1/.gradle/caches/data" ]
  [ -e "$BATS_TEST_TMPDIR/c1/session/data" ]
  [ -e "$BATS_TEST_TMPDIR/victim/keep/data" ]
}

@test "leftovers: thousands of skipped units still print the remove result" {
  local pad
  pad=$(printf 'x%.0s' {1..200})
  mkdir -p "$DISKDIET_CLAUDE_TMP"
  seq -f "$DISKDIET_CLAUDE_TMP/s%g_$pad" 4500 | xargs mkdir
  run_script "$LEFTOVERS" remove claude-tmp
  [ "$status" -eq 0 ]
  [ "$(field '[(.removed | length), (.skipped | length)]')" = '[0,4500]' ]
}

@test "leftovers: an unknown id removes nothing and exits 2" {
  unit "$HOME/.android/avd/Pixel.avd" old
  for id in nope '.*' 'android-avd|x' "android-avd${NL}x"; do
    run_script "$LEFTOVERS" remove android-avd "$id"
    [ "$status" -eq 2 ]
    [ -e "$HOME/.android/avd/Pixel.avd/data" ]
    grep -qF "unknown id: $id" <<<"$stderr"
  done
}

@test "leftovers: usage errors exit 2" {
  for args in "" "remove" "bogus" "list x"; do
    # shellcheck disable=SC2086 # split on purpose
    run_script "$LEFTOVERS" $args
    [ "$status" -eq 2 ]
    grep -qF 'usage:' <<<"$stderr"
  done
}

@test "leftovers: unset HOME exits 2" {
  HOME="" run_script "$LEFTOVERS" list
  [ "$status" -eq 2 ]
  grep -qF 'HOME is not set' <<<"$stderr"
}

@test "leftovers: DerivedData of a project built in the last 30 days is not a unit" {
  unit "$HOME/Library/Developer/Xcode/DerivedData/Old-abc" old
  unit "$HOME/Library/Developer/Xcode/DerivedData/Recent-abc" old
  touch -t "$(date -v-10d +%Y%m%d%H%M)" "$HOME/Library/Developer/Xcode/DerivedData/Recent-abc/data"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].units[].path | sub(".*/"; "")]')" = '["Old-abc"]' ]
}

@test "leftovers: simulator devices shut down and unused for 30 days are listed with their size" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_devices.json simctl list devices -j
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.simulator_devices[] | [.udid[-1:], .name, .gb]]')" = '[["1","Old Shutdown",1],["5","Old Too",2]]' ]
  [ "$(field .simulator_devices_gb)" = 3 ]
}

@test "leftovers: a device list simctl cannot give leaves simulator devices unknown" {
  stub_output xcode-select xcode_select_p.txt -p
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field .simulator_devices)" = null ]
  [ "$(field .simulator_devices_gb)" = null ]
}

@test "leftovers: simulator devices are removed by simctl delete with their udids" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_devices.json simctl list devices -j
  STUB_XCRUN=/dev/null run_script "$LEFTOVERS" remove simulator-devices
  [ "$status" -eq 0 ]
  [ "$(grep 'simctl delete' "$STUB_LOG")" = "xcrun simctl delete 00000000-0000-0000-0000-000000000001${NL}xcrun simctl delete 00000000-0000-0000-0000-000000000005" ]
  [ "$(field .removed)" = '["simulator-devices"]' ]
}

@test "leftovers: no old simulator device deletes nothing" {
  stub_output xcode-select xcode_select_p.txt -p
  printf '{"devices":{}}' >"$BATS_TEST_TMPDIR/none.json"
  local devices="$BATS_TEST_TMPDIR/none.json"
  STUB_XCRUN_SIMCTL_LIST_DEVICES_J=$devices run_script "$LEFTOVERS" remove simulator-devices
  [ "$status" -eq 0 ]
  [ "$(grep -c 'simctl delete' "$STUB_LOG")" = 0 ]
  [ "$(field '[.removed, .errors]')" = '[[],[]]' ]
}

@test "leftovers: a failing simctl delete or device list is reported as an error" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_devices.json simctl list devices -j
  run_script "$LEFTOVERS" remove simulator-devices
  [ "$status" -eq 0 ]
  field '.errors[0]' | grep -qF 'simulator-devices'
  unset STUB_XCRUN_SIMCTL_LIST_DEVICES_J
  run_script "$LEFTOVERS" remove simulator-devices
  [ "$status" -eq 0 ]
  field '.errors[0]' | grep -qF 'simulator-devices'
}

@test "leftovers: without developer tools simulator devices are an error, xcrun never called" {
  run_script "$LEFTOVERS" remove simulator-devices
  [ "$status" -eq 0 ]
  [ "$(grep -c '^xcrun ' "$STUB_LOG")" = 0 ]
  field '.errors[0]' | grep -qF 'simulator-devices: developer tools are not installed'
}

@test "leftovers: a clean, old worktree whose commits are on main or a remote is a unit" {
  repo_with_worktree app
  repo_with_worktree pushed
  wt_commit "$HOME/Projects/pushed-wt" feature
  git -C "$HOME/Projects/pushed" update-ref refs/remotes/origin/wt wt
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "git-worktrees") | .units[].path | sub(".*/"; "")] | sort')" = '["app-wt","pushed-wt"]' ]
}

@test "leftovers: a worktree with changes, hidden, ignored or skip-worktree files, submodules, unpushed commits, recent files, a lock, no folder, a filter in its repo config or no main HEAD is not a unit" {
  repo_with_worktree dirty
  printf 'x' >"$HOME/Projects/dirty-wt/new.txt"
  touch -t 202001010000 "$HOME/Projects/dirty-wt/new.txt" "$HOME/Projects/dirty-wt"
  repo_with_worktree ahead
  wt_commit "$HOME/Projects/ahead-wt" local-only
  find "$HOME/Projects/ahead-wt" -exec touch -h -t 202001010000 {} +
  repo_with_worktree recent
  touch -t "$(date -v-10d +%Y%m%d%H%M)" "$HOME/Projects/recent-wt"
  repo_with_worktree locked
  git -C "$HOME/Projects/locked" worktree lock "$HOME/Projects/locked-wt"
  repo_with_worktree gone
  mv "$HOME/Projects/gone-wt" "$HOME/Projects/gone-moved"
  repo_with_worktree hidden
  git -C "$HOME/Projects/hidden" config status.showUntrackedFiles no
  printf 'x' >"$HOME/Projects/hidden-wt/notes.txt"
  repo_with_worktree ignored
  mkdir -p "$HOME/Projects/ignored/.git/info"
  printf '.env\n' >>"$HOME/Projects/ignored/.git/info/exclude"
  printf 'x' >"$HOME/Projects/ignored-wt/.env"
  repo_with_worktree filtered
  git -C "$HOME/Projects/filtered" config filter.x.clean cat
  repo_with_worktree unborn
  git -C "$HOME/Projects/unborn" checkout -q --orphan fresh
  repo_with_worktree skipped
  printf 'a\n' >"$HOME/Projects/skipped-wt/cfg"
  git -C "$HOME/Projects/skipped-wt" add cfg
  wt_commit "$HOME/Projects/skipped-wt" cfg
  git -C "$HOME/Projects/skipped" merge -q wt
  git -C "$HOME/Projects/skipped-wt" update-index --skip-worktree cfg
  printf 'local edit\n' >"$HOME/Projects/skipped-wt/cfg"
  repo_with_worktree modules
  printf '[submodule "sm"]\n' >"$HOME/Projects/modules-wt/.gitmodules"
  git -C "$HOME/Projects/modules-wt" add .gitmodules
  wt_commit "$HOME/Projects/modules-wt" modules
  git -C "$HOME/Projects/modules" merge -q wt
  repo_with_worktree gitlink
  git init -q "$HOME/Projects/gitlink-wt/sub"
  git -C "$HOME/Projects/gitlink-wt/sub" -c user.name=t -c user.email=t@t commit -q --allow-empty -m sub
  git -C "$HOME/Projects/gitlink-wt" add sub 2>/dev/null
  wt_commit "$HOME/Projects/gitlink-wt" gitlink
  git -C "$HOME/Projects/gitlink" merge -q wt
  find "$HOME/Projects" -exec touch -h -t 202001010000 {} +
  touch -t "$(date -v-10d +%Y%m%d%H%M)" "$HOME/Projects/recent-wt"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "git-worktrees")]')" = '[]' ]
}

@test "leftovers: remove takes a worktree out through git, not rm" {
  repo_with_worktree app
  run_script "$LEFTOVERS" remove git-worktrees
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Projects/app-wt" ]
  [ "$(git -C "$HOME/Projects/app" worktree list | wc -l | tr -d ' ')" = 1 ]
  [ "$(field '[.removed[] | sub(".*/"; "")]')" = '["app-wt"]' ]
}

@test "leftovers: a worktree git refuses to remove is reported as an error" {
  repo_with_worktree app
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh
case "$*" in *"worktree remove"*) echo "fatal: busy" >&2; exit 128;; esac
exec /usr/bin/git "$@"
' >"$BATS_TEST_TMPDIR/bin/git"
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$LEFTOVERS" remove git-worktrees
  [ "$status" -eq 0 ]
  [ -e "$HOME/Projects/app-wt" ]
  field '.errors[0]' | grep -qF 'fatal: busy'
  [ "$(field .removed)" = '[]' ]
}

@test "leftovers: a repo's own git config never runs a command during the scan" {
  repo_with_worktree app
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$BATS_TEST_TMPDIR" >"$BATS_TEST_TMPDIR/hook"
  chmod +x "$BATS_TEST_TMPDIR/hook"
  git -C "$HOME/Projects/app" config core.fsmonitor "$BATS_TEST_TMPDIR/hook"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "leftovers: a filter in a repo's config never runs during the scan" {
  repo_with_worktree app
  printf '* filter=x\n' >"$HOME/Projects/app-wt/.gitattributes"
  git -C "$HOME/Projects/app-wt" add .gitattributes
  wt_commit "$HOME/Projects/app-wt" attrs
  git -C "$HOME/Projects/app" merge -q wt
  find "$HOME/Projects" -exec touch -h -t 202001010000 {} +
  git -C "$HOME/Projects/app" config filter.x.clean "touch $BATS_TEST_TMPDIR/ran; cat"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  [ "$(field '[.items[] | select(.id == "git-worktrees")]')" = '[]' ]
}

@test "leftovers: a worktree gone after a failed git remove counts as removed" {
  repo_with_worktree app
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\ncase "$*" in *"worktree remove"*) rm -rf "%s"; echo "warning: gone" >&2; exit 1;; esac\nexec /usr/bin/git "$@"\n' "$HOME/Projects/app-wt" >"$BATS_TEST_TMPDIR/bin/git"
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$LEFTOVERS" remove git-worktrees
  [ "$status" -eq 0 ]
  [ "$(field '[.removed[] | sub(".*/"; "")]')" = '["app-wt"]' ]
}

@test "leftovers: a device record with a bad udid or size is never listed or deleted" {
  stub_output xcode-select xcode_select_p.txt -p
  cat >"$BATS_TEST_TMPDIR/bad.json" <<'JSON'
{"devices":{"r":[
 {"dataPath":"/private/tmp/simdev/7/data","udid":"all","name":"Keyword","state":"Shutdown","lastUsedAt":"2020-01-01T00:00:00Z","dataPathSize":1},
 {"dataPath":"/private/tmp/simdev/7/data","name":"No udid","state":"Shutdown","lastUsedAt":"2020-01-01T00:00:00Z","dataPathSize":1},
 {"udid":"00000000-0000-0000-0000-000000000008","dataPath":"relative/8","name":"Relative","state":"Shutdown","lastUsedAt":"2020-01-01T00:00:00Z","dataPathSize":1},
 {"dataPath":"/private/tmp/simdev/7/data","udid":"00000000-0000-0000-0000-000000000007","name":"Text size","state":"Shutdown","lastUsedAt":"2020-01-01T00:00:00Z","dataPathSize":"12"}
]}}
JSON
  local devices="$BATS_TEST_TMPDIR/bad.json"
  STUB_XCRUN_SIMCTL_LIST_DEVICES_J=$devices run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.simulator_devices[] | [.name, .gb]]')" = '[["Text size",null]]' ]
  STUB_XCRUN=/dev/null STUB_XCRUN_SIMCTL_LIST_DEVICES_J=$devices run_script "$LEFTOVERS" remove simulator-devices
  grep -qxF 'xcrun simctl delete 00000000-0000-0000-0000-000000000007' "$STUB_LOG"
}

@test "leftovers: a device whose data folder guard refuses is skipped, not deleted" {
  stub_output xcode-select xcode_select_p.txt -p
  mkdir -p "$HOME/.config/mole"
  printf '%s\n' "\$HOME/Library/Developer/CoreSimulator/Devices/1/device.plist" >"$HOME/.config/mole/whitelist"
  sed "s|\"name\": \"Old Shutdown\"|\"dataPath\": \"$HOME/Library/Developer/CoreSimulator/Devices/1/data\", &|" "$FIXTURES_DIR/simctl_devices.json" >"$BATS_TEST_TMPDIR/d.json"
  local devices="$BATS_TEST_TMPDIR/d.json"
  STUB_XCRUN=/dev/null STUB_XCRUN_SIMCTL_LIST_DEVICES_J=$devices run_script "$LEFTOVERS" remove simulator-devices
  [ "$status" -eq 0 ]
  grep -qxF 'xcrun simctl delete 00000000-0000-0000-0000-000000000005' "$STUB_LOG"
  field '.skipped[0].reason' | grep -qF 'refused:'
}

@test "leftovers: a repo git cannot read never brings back the previous repo's worktree" {
  git init -q -b main "$HOME/Projects/bbb"
  git -C "$HOME/Projects/bbb" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  mkdir -p "$HOME/Projects/ccc/.git" "$HOME/Projects/aaa/.git"
  find "$HOME/Projects" -exec touch -h -t 202001010000 {} +
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "git-worktrees")]')" = '[]' ]
}

@test "leftovers: a repo whose config can make git fetch or run a program is never scanned" {
  local key
  for key in extensions.partialClone remote.origin.uploadpack core.sshCommand; do
    rm -rf "$HOME/Projects"
    repo_with_worktree app
    git -C "$HOME/Projects/app" config "$key" "touch $BATS_TEST_TMPDIR/ran"
    run_script "$LEFTOVERS" list
    [ "$status" -eq 0 ]
    [ "$(field '[.items[] | select(.id == "git-worktrees")]')" = '[]' ]
  done
}

@test "leftovers: a driver in the owner's global git config does not hide worktrees" {
  repo_with_worktree app
  git config --global filter.lfs.clean "git-lfs clean -- %f"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "git-worktrees") | .units[].path | sub(".*/"; "")]')" = '["app-wt"]' ]
}

@test "leftovers: a worktree path with a pattern character stays literal" {
  repo_with_worktree app
  git -C "$HOME/Projects/app" worktree move "$HOME/Projects/app-wt" "$HOME/Projects/app-[w]t"
  mkdir -p "$HOME/Projects/app-wt"
  find "$HOME/Projects" -exec touch -h -t 202001010000 {} +
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "git-worktrees") | .units[].path | sub(".*/"; "")]')" = '["app-[w]t"]' ]
}

@test "leftovers: a newline in a worktree path never makes another path a unit" {
  repo_with_worktree app
  git -C "$HOME/Projects/app" worktree add -q "$HOME/Projects/x${NL}${NL}worktree $HOME/Projects/app" -b nl
  git -C "$HOME/Projects/app" worktree add -q "$HOME/Projects/y${NL}$HOME/Projects/app-wt" -b nl2
  find "$HOME/Projects" -exec touch -h -t 202001010000 {} +
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "git-worktrees") | .units[].path | sub(".*/"; "")]')" = '["app-wt"]' ]
}

@test "leftovers: a worktree holding a .git folder git status cannot see is not a unit" {
  repo_with_worktree lower
  mkdir -p "$HOME/Projects/lower-wt/notes/.git"
  printf 'x' >"$HOME/Projects/lower-wt/notes/.git/keep"
  repo_with_worktree mixed
  mkdir -p "$HOME/Projects/mixed-wt/a/.Git"
  printf 'x' >"$HOME/Projects/mixed-wt/a/.Git/keep"
  find "$HOME/Projects" -exec touch -h -t 202001010000 {} +
  run_script "$LEFTOVERS" remove git-worktrees
  [ "$status" -eq 0 ]
  [ -e "$HOME/Projects/lower-wt/notes/.git/keep" ]
  [ -e "$HOME/Projects/mixed-wt/a/.Git/keep" ]
  [ "$(field .removed)" = '[]' ]
}

@test "leftovers: a worktree reached from two .git folders is one unit" {
  repo_with_worktree app
  mkdir -p "$HOME/Projects/app/tmp/.git"
  printf '/tmp/\n' >>"$HOME/Projects/app/.git/info/exclude"
  find "$HOME/Projects" -exec touch -h -t 202001010000 {} +
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "git-worktrees") | .count]')" = '[1]' ]
}

@test "leftovers: a Projects folder that is a symlink is scanned" {
  repo_with_worktree app
  mv "$HOME/Projects" "$BATS_TEST_TMPDIR/real"
  ln -s "$BATS_TEST_TMPDIR/real" "$HOME/Projects"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "git-worktrees") | .units[].path | sub(".*/"; "")]')" = '["app-wt"]' ]
}

@test "leftovers: a device list of two documents leaves devices unknown, a repeated device is deleted once" {
  stub_output xcode-select xcode_select_p.txt -p
  unit "$HOME/.cache/uv" old
  cat "$FIXTURES_DIR/simctl_devices.json" "$FIXTURES_DIR/simctl_devices.json" >"$BATS_TEST_TMPDIR/two.json"
  STUB_XCRUN_SIMCTL_LIST_DEVICES_J="$BATS_TEST_TMPDIR/two.json" run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.simulator_devices, (.items | length)]')" = '[null,1]' ]
  /usr/bin/jq '.devices.r = .devices["com.apple.CoreSimulator.SimRuntime.iOS-26-0"]' "$FIXTURES_DIR/simctl_devices.json" >"$BATS_TEST_TMPDIR/dup.json"
  STUB_XCRUN=/dev/null STUB_XCRUN_SIMCTL_LIST_DEVICES_J="$BATS_TEST_TMPDIR/dup.json" run_script "$LEFTOVERS" remove simulator-devices
  [ "$status" -eq 0 ]
  [ "$(grep 'simctl delete' "$STUB_LOG")" = "xcrun simctl delete 00000000-0000-0000-0000-000000000001${NL}xcrun simctl delete 00000000-0000-0000-0000-000000000005" ]
}

# ten_days_old <path>: dates every file under path to ten days ago.
ten_days_old() { find "$1" -exec touch -h -t "$(date -v-10d +%Y%m%d%H%M)" {} +; }

@test "leftovers max: DerivedData built in the last 30 days is a unit" {
  unit "$HOME/Library/Developer/Xcode/DerivedData/App-abc"
  ten_days_old "$HOME/Library/Developer/Xcode/DerivedData/App-abc"
  run_script "$LEFTOVERS" list --max
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '["xcode-derived-data"]' ]
  run_script "$LEFTOVERS" list
  [ "$(field '.items')" = '[]' ]
}

@test "leftovers max: every shut-down simulator device is listed, booted or just used ones are kept" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_devices.json simctl list devices -j
  run_script "$LEFTOVERS" list --max
  [ "$status" -eq 0 ]
  [ "$(field '[.simulator_devices[].udid[-1:]]')" = '["1","4","5"]' ]
}

@test "leftovers max: devices are deleted with every shut-down udid" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_devices.json simctl list devices -j
  STUB_XCRUN=/dev/null run_script "$LEFTOVERS" remove --max simulator-devices
  [ "$status" -eq 0 ]
  [ "$(grep 'simctl delete' "$STUB_LOG")" = "xcrun simctl delete 00000000-0000-0000-0000-000000000001${NL}xcrun simctl delete 00000000-0000-0000-0000-000000000004${NL}xcrun simctl delete 00000000-0000-0000-0000-000000000005" ]
}

@test "leftovers max: every runtime but the newest of its platform is listed and sized" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_runtime_list_many.json simctl runtime list -j
  stub_output xcrun simctl_devices.json simctl list devices -j
  run_script "$LEFTOVERS" list --max
  [ "$status" -eq 0 ]
  [ "$(field .simulator_runtimes)" = '["Would delete 00000000-0000-0000-0000-000000000013 com.apple.platform.iphonesimulator (9.3)","Would delete 00000000-0000-0000-0000-000000000011 com.apple.platform.iphonesimulator (26.5)"]' ]
  [ "$(field .simulator_runtimes_gb)" = 3 ]
  [ "$(grep -c 'notUsedSinceDays' "$STUB_LOG")" = 0 ]
}

@test "leftovers max: old runtimes are deleted one by one, the newest kept" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_runtime_list_many.json simctl runtime list -j
  stub_output xcrun simctl_devices.json simctl list devices -j
  STUB_XCRUN=/dev/null run_script "$LEFTOVERS" remove --max simulator-runtimes
  [ "$status" -eq 0 ]
  [ "$(grep 'runtime delete' "$STUB_LOG")" = "xcrun simctl runtime delete 00000000-0000-0000-0000-000000000013${NL}xcrun simctl runtime delete 00000000-0000-0000-0000-000000000011" ]
  [ "$(field .removed)" = '["simulator-runtimes"]' ]
}

@test "leftovers max: a runtime list simctl cannot give is an error, nothing deleted" {
  stub_output xcode-select xcode_select_p.txt -p
  run_script "$LEFTOVERS" remove --max simulator-runtimes
  [ "$status" -eq 0 ]
  field '.errors[0]' | grep -qF 'simulator-runtimes'
  [ "$(grep -c 'runtime delete' "$STUB_LOG")" = 0 ]
}

@test "leftovers max: a failing runtime delete is reported as an error" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_runtime_list_many.json simctl runtime list -j
  stub_output xcrun simctl_devices.json simctl list devices -j
  run_script "$LEFTOVERS" remove --max simulator-runtimes
  [ "$status" -eq 0 ]
  field '.errors[0]' | grep -qF 'simulator-runtimes'
}

@test "leftovers: Xcode previews, XcodeBuildMCP, temp folders and the npm cache are units" {
  unit "$HOME/Library/Developer/Xcode/UserData/Previews" old
  unit "$HOME/Library/Developer/XcodeBuildMCP/logs" old
  unit "${TMPDIR}tmp.AbC123" old
  unit "${TMPDIR}pytest-of-me" old
  unit "${TMPDIR}com.apple.keep" old
  unit "$HOME/.npm/_cacache" old
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '["npm-cache","tmpdir-temp","xcode-previews","xcodebuildmcp"]' ]
  [ "$(field '[.items[] | select(.id == "tmpdir-temp") | .units[].path | sub(".*/"; "")] | sort')" = '["pytest-of-me","tmp.AbC123"]' ]
}

@test "leftovers: git-ignored build folders under Projects with no tracked file are units" {
  local r="$HOME/Projects/app"
  git init -q -b main "$r"
  printf 'node_modules/\nbuild/\n' >"$r/.gitignore"
  mkdir -p "$r/src/build"
  printf x >"$r/src/build/keep.txt"
  git -C "$r" add .gitignore
  git -C "$r" add -f src/build/keep.txt
  unit "$r/node_modules" old
  unit "$r/web/dist" old
  unit "$HOME/Projects/loose/node_modules" old
  touch -t 202001010000 "$r/src/build/keep.txt"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "project-build-dirs") | .units[].path | sub(".*/Projects/"; "")]')" = '["app/node_modules"]' ]
}

@test "leftovers: a build folder in a repo whose config runs programs is not a unit" {
  local r="$HOME/Projects/app"
  git init -q -b main "$r"
  printf 'node_modules/\n' >"$r/.gitignore"
  # shellcheck disable=SC2016 # expanded by the filter, not the test
  git -C "$r" config filter.x.clean 'touch "$HOME/ran"'
  unit "$r/node_modules" old
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '[]' ]
  [ ! -e "$HOME/ran" ]
}

@test "leftovers: Chrome code-sign clones are left out of restart space" {
  mkdir -p "$BATS_TEST_TMPDIR/folders/X/com.google.Chrome.code_sign_clone/c1"
  head -c 20971520 /dev/zero >"$BATS_TEST_TMPDIR/folders/X/com.google.Chrome.code_sign_clone/c1/big"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '.restart_gb')" = 0 ]
}

@test "leftovers max: a bad flag or remove without ids exits 2" {
  run_script "$LEFTOVERS" list --all
  [ "$status" -eq 2 ]
  run_script "$LEFTOVERS" remove --max
  [ "$status" -eq 2 ]
}

@test "leftovers max: one runtime per platform lists none and deletes nothing, no error" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_devices.json simctl list devices -j
  printf '{"00000000-0000-0000-0000-000000000012": {"identifier": "00000000-0000-0000-0000-000000000012", "platformIdentifier": "p", "version": "27.1", "sizeBytes": 1}}' >"$BATS_TEST_TMPDIR/one.json"
  STUB_XCRUN_SIMCTL_RUNTIME_LIST_J="$BATS_TEST_TMPDIR/one.json" run_script "$LEFTOVERS" list --max
  [ "$status" -eq 0 ]
  [ "$(field .simulator_runtimes)" = '[]' ]
  STUB_XCRUN_SIMCTL_RUNTIME_LIST_J="$BATS_TEST_TMPDIR/one.json" run_script "$LEFTOVERS" remove --max simulator-runtimes
  [ "$status" -eq 0 ]
  [ "$(field '[.removed, .errors]')" = '[[],[]]' ]
  [ "$(grep -c 'runtime delete' "$STUB_LOG")" = 0 ]
}

@test "leftovers max: a runtime list simctl cannot give leaves runtimes unknown" {
  stub_output xcode-select xcode_select_p.txt -p
  run_script "$LEFTOVERS" list --max
  [ "$status" -eq 0 ]
  [ "$(field .simulator_runtimes)" = null ]
}

@test "leftovers: a glob character in TMPDIR exits 2" {
  TMPDIR="$BATS_TEST_TMPDIR/a*b/" run_script "$LEFTOVERS" list
  [ "$status" -eq 2 ]
}

@test "leftovers: other folders in X count toward restart space" {
  mkdir -p "$BATS_TEST_TMPDIR/folders/X/com.example.app"
  head -c 20971520 /dev/zero >"$BATS_TEST_TMPDIR/folders/X/com.example.app/big"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '.restart_gb')" = 0.02 ]
}

@test "leftovers: a build folder that is its own git checkout is not a unit" {
  local r="$HOME/Projects/app"
  git init -q -b main "$r"
  printf 'dist/\n' >"$r/.gitignore"
  git init -q -b main "$r/dist"
  unit "$r/dist" old
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '[]' ]
}

@test "leftovers: a build folder git cannot list the files of is not a unit" {
  local r="$HOME/Projects/app" bin="$BATS_TEST_TMPDIR/bin"
  git init -q -b main "$r"
  printf 'node_modules/\n' >"$r/.gitignore"
  unit "$r/node_modules" old
  mkdir -p "$bin"
  # shellcheck disable=SC2016 # expanded by the fake git
  printf '#!/bin/bash\nfor a; do [ "$a" != ls-files ] || exit 128; done\nexec %s "$@"\n' "$(command -v git)" >"$bin/git"
  chmod +x "$bin/git"
  PATH="$bin:$PATH" run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '[]' ]
}

@test "leftovers: temp folders in a TMPDIR that is a symlink are not units" {
  mkdir -p "$BATS_TEST_TMPDIR/real"
  unit "$BATS_TEST_TMPDIR/real/tmp.AbC123" old
  ln -s "$BATS_TEST_TMPDIR/real" "$BATS_TEST_TMPDIR/folders/L"
  TMPDIR="$BATS_TEST_TMPDIR/folders/L/" run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '[]' ]
}

# runtimes <json>: the runtime list simctl prints for this test.
runtimes() {
  stub_output xcode-select xcode_select_p.txt -p
  printf '%s' "$1" >"$BATS_TEST_TMPDIR/rt.json"
  export STUB_XCRUN_SIMCTL_RUNTIME_LIST_J="$BATS_TEST_TMPDIR/rt.json"
  stub_output xcrun simctl_devices.json simctl list devices -j
}

@test "leftovers max: only ready, deletable runtimes unused for 2 hours are deleted, the newest ready one kept" {
  local id='00000000-0000-0000-0000-0000000000'
  runtimes "{
    \"a\": {\"identifier\": \"${id}21\", \"runtimeIdentifier\": \"r21\", \"platformIdentifier\": \"p\", \"version\": \"1.0\", \"state\": \"Ready\", \"deletable\": true, \"lastUsedAt\": \"2020-01-01T00:00:00Z\"},
    \"b\": {\"identifier\": \"${id}22\", \"runtimeIdentifier\": \"r22\", \"platformIdentifier\": \"p\", \"version\": \"9.0\", \"state\": \"Downloading\", \"deletable\": true},
    \"c\": {\"identifier\": \"${id}23\", \"runtimeIdentifier\": \"r23\", \"platformIdentifier\": \"p\", \"version\": \"2.0\", \"state\": \"Ready\", \"deletable\": true},
    \"d\": {\"identifier\": \"${id}24\", \"runtimeIdentifier\": \"r24\", \"platformIdentifier\": \"p\", \"version\": \"1.5\", \"state\": \"Ready\", \"deletable\": true, \"lastUsedAt\": \"2099-01-01T00:00:00Z\"},
    \"e\": {\"identifier\": \"${id}25\", \"runtimeIdentifier\": \"r25\", \"platformIdentifier\": \"p\", \"version\": 5, \"state\": \"Ready\", \"deletable\": true},
    \"f\": {\"identifier\": \"${id}26\", \"runtimeIdentifier\": \"r26\", \"platformIdentifier\": \"p\", \"version\": \"0.5\", \"state\": \"Ready\", \"deletable\": false}
  }"
  run_script "$LEFTOVERS" list --max
  [ "$status" -eq 0 ]
  [ "$(field .simulator_runtimes)" = "[\"Would delete ${id}21 p (1.0)\"]" ]
}

@test "leftovers max: each runtime delete is reported, a failure does not hide the ones deleted" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_runtime_list_many.json simctl runtime list -j
  stub_output xcrun simctl_devices.json simctl list devices -j
  stub_output xcrun simctl_runtime_dry_run.txt simctl runtime delete 00000000-0000-0000-0000-000000000013
  run_script "$LEFTOVERS" remove --max simulator-runtimes
  [ "$status" -eq 0 ]
  [ "$(field .removed)" = '["simulator-runtimes"]' ]
  [ "$(field '.errors | length')" = 1 ]
  field '.errors[0]' | grep -qF 'simulator-runtimes: 00000000-0000-0000-0000-000000000011'
}

@test "leftovers: a build folder whose path holds a newline is not a unit" {
  local r="$HOME/Projects/app"
  git init -q -b main "$r"
  printf 'node_modules/\n' >"$r/.gitignore"
  unit "$r/a${NL}b/node_modules" old
  mkdir "$r/a"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '[]' ]
}

@test "leftovers: thousands of temp folders are listed in under 60 s" {
  seq -f "${TMPDIR}tmp.%g" 2000 | xargs mkdir
  find "$TMPDIR" -exec touch -t 202001010000 {} +
  mkdir "${TMPDIR}tmp.new"
  SECONDS=0
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  echo "took ${SECONDS}s" >&3
  [ "$SECONDS" -lt 60 ]
  [ "$(field '.items[] | select(.id == "tmpdir-temp") | [.count, .in_use]')" = '[2001,1]' ]
}

@test "leftovers: a build folder ignored only by a repo above Projects is not a unit" {
  git init -q -b main "$HOME"
  printf '*\n' >"$HOME/.gitignore"
  unit "$HOME/Projects/notes/build" old
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '[]' ]
}

@test "leftovers: hard-linked files count in every unit that holds them" {
  mkdir -p "$HOME/.gradle/caches" "$HOME/.cache/uv"
  head -c 20971520 /dev/zero >"$HOME/.gradle/caches/big"
  ln "$HOME/.gradle/caches/big" "$HOME/.cache/uv/big"
  find "$HOME" -exec touch -t 202001010000 {} +
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].gb]')" = '[0.02,0.02]' ]
}

@test "leftovers: a device whose folder changed in the last 2 hours is skipped, not deleted" {
  stub_output xcode-select xcode_select_p.txt -p
  sed "s|/private/tmp/simdev/4/data|$HOME/dev/4/data|" "$FIXTURES_DIR/simctl_devices.json" >"$BATS_TEST_TMPDIR/d.json"
  mkdir -p "$HOME/dev/4/data"
  STUB_XCRUN=/dev/null STUB_XCRUN_SIMCTL_LIST_DEVICES_J="$BATS_TEST_TMPDIR/d.json" run_script "$LEFTOVERS" remove --max simulator-devices
  [ "$status" -eq 0 ]
  [ "$(grep -c "simctl delete $(printf '%s' 00000000-0000-0000-0000-000000000004)" "$STUB_LOG")" = 0 ]
  [ "$(field '.skipped[0].path')" = "\"$HOME/dev/4\"" ]
}

@test "leftovers: each device delete is reported, a failure does not hide the ones deleted" {
  stub_output xcode-select xcode_select_p.txt -p
  stub_output xcrun simctl_devices.json simctl list devices -j
  stub_output xcrun simctl_runtime_dry_run.txt simctl delete 00000000-0000-0000-0000-000000000001
  run_script "$LEFTOVERS" remove simulator-devices
  [ "$status" -eq 0 ]
  [ "$(field .removed)" = '["simulator-devices"]' ]
  [ "$(field '.errors | length')" = 1 ]
  field '.errors[0]' | grep -qF 'simulator-devices: 00000000-0000-0000-0000-000000000005'
}

@test "leftovers: temp folders counted as units are left out of restart space" {
  mkdir -p "${TMPDIR}tmp.big"
  head -c 20971520 /dev/zero >"${TMPDIR}tmp.big/f"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '.restart_gb')" = 0 ]
}

@test "leftovers: a whitelisted temp folder is protected" {
  unit "${TMPDIR}tmp.keep" old
  unit "${TMPDIR}tmp.go" old
  mkdir -p "$HOME/.config/mole"
  printf '%s\n' "${TMPDIR}tmp.keep" >"$HOME/.config/mole/whitelist"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "tmpdir-temp") | .units[] | [(.path | sub(".*/"; "")), (.protected != null)]] | sort')" = '[["tmp.go",false],["tmp.keep",true]]' ]
}

@test "leftovers: a temp folder that links to a protected folder is protected" {
  unit "$HOME/secret" old
  mkdir -p "$HOME/.config/mole"
  printf '%s\n' "$HOME/secret" >"$HOME/.config/mole/whitelist"
  ln -s "$HOME/secret" "${TMPDIR}tmp.link"
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "tmpdir-temp") | .units[].protected != null]')" = '[true]' ]
}

@test "leftovers: a guard that cannot check marks every listed unit with its first line" {
  unset DISKDIET_MOLE_LIB
  unit "$HOME/.android/avd/Pixel.avd" old
  PATH="/usr/bin:/bin" run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  field '.items[0].units[0].protected' | grep -qF 'could not check: '
  [ "$(field '.items[0].units[0].protected | test("\n")')" = false ]
}

@test "leftovers max: a runtime a booted device runs on is neither listed nor deleted" {
  local id='00000000-0000-0000-0000-0000000000'
  runtimes "{
    \"a\": {\"identifier\": \"${id}31\", \"runtimeIdentifier\": \"r1\", \"platformIdentifier\": \"p\", \"version\": \"1.0\", \"state\": \"Ready\", \"deletable\": true},
    \"b\": {\"identifier\": \"${id}32\", \"runtimeIdentifier\": \"r2\", \"platformIdentifier\": \"p\", \"version\": \"2.0\", \"state\": \"Ready\", \"deletable\": true}
  }"
  printf '{"devices": {"r1": [{"udid": "u", "state": "Booted"}], "r2": []}}' >"$BATS_TEST_TMPDIR/dev.json"
  STUB_XCRUN_SIMCTL_LIST_DEVICES_J="$BATS_TEST_TMPDIR/dev.json" run_script "$LEFTOVERS" list --max
  [ "$status" -eq 0 ]
  [ "$(field .simulator_runtimes)" = '[]' ]
  STUB_XCRUN_SIMCTL_LIST_DEVICES_J="$BATS_TEST_TMPDIR/dev.json" run_script "$LEFTOVERS" remove --max simulator-runtimes
  [ "$status" -eq 0 ]
  [ "$(grep -c 'runtime delete' "$STUB_LOG")" = 0 ]
}

@test "leftovers max: a runtime whose devices simctl cannot list is not deleted" {
  local id='00000000-0000-0000-0000-0000000000'
  runtimes "{
    \"a\": {\"identifier\": \"${id}31\", \"runtimeIdentifier\": \"r1\", \"platformIdentifier\": \"p\", \"version\": \"1.0\", \"state\": \"Ready\", \"deletable\": true},
    \"b\": {\"identifier\": \"${id}32\", \"runtimeIdentifier\": \"r2\", \"platformIdentifier\": \"p\", \"version\": \"2.0\", \"state\": \"Ready\", \"deletable\": true}
  }"
  unset STUB_XCRUN_SIMCTL_LIST_DEVICES_J
  run_script "$LEFTOVERS" remove --max simulator-runtimes
  [ "$status" -eq 0 ]
  [ "$(grep -c 'runtime delete' "$STUB_LOG")" = 0 ]
  [ "$(field .errors)" = '["simulator-runtimes: simctl could not list runtimes"]' ]
}

@test "leftovers max: a runtime id that is not a UUID is never deleted" {
  runtimes '{
    "a": {"identifier": "all", "runtimeIdentifier": "r1", "platformIdentifier": "p", "version": "1.0", "state": "Ready", "deletable": true},
    "b": {"identifier": "00000000-0000-0000-0000-000000000032", "runtimeIdentifier": "r2", "platformIdentifier": "p", "version": "2.0", "state": "Ready", "deletable": true}
  }'
  printf '{"devices": {}}' >"$BATS_TEST_TMPDIR/dev.json"
  STUB_XCRUN_SIMCTL_LIST_DEVICES_J="$BATS_TEST_TMPDIR/dev.json" run_script "$LEFTOVERS" remove --max simulator-runtimes
  [ "$status" -eq 0 ]
  [ "$(grep -c 'runtime delete' "$STUB_LOG")" = 0 ]
}

@test "leftovers: units in use are never measured, however many" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -s "$TESTS_DIR/stubs/_stub" "$BATS_TEST_TMPDIR/bin/du"
  unit "$HOME/.android/avd/A.avd"
  unit "$HOME/.android/avd/B.avd"
  unit "$HOME/.android/avd/C.avd" old
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  grep -q 'C.avd' "$STUB_LOG"
  [ "$(grep -cE '[AB]\.avd' "$STUB_LOG")" = 0 ]
}

@test "leftovers: a folder under TMPDIR reached through a symlink still goes through guard" {
  unit "$HOME/secret/claude/s1" old
  mkdir -p "$HOME/.config/mole"
  printf '%s\n' "$HOME/secret" >"$HOME/.config/mole/whitelist"
  ln -s "$HOME/secret" "${TMPDIR}link"
  DISKDIET_CLAUDE_TMP="${TMPDIR}link/claude" run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[] | select(.id == "claude-tmp") | .units[].protected != null]')" = '[true]' ]
}

@test "leftovers: a build folder with a subfolder find cannot read is not a unit" {
  local r="$HOME/Projects/app"
  git init -q -b main "$r"
  printf 'node_modules/\n' >"$r/.gitignore"
  unit "$r/node_modules/locked" old
  chmod 000 "$r/node_modules/locked"
  run_script "$LEFTOVERS" list
  chmod 755 "$r/node_modules/locked"
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '[]' ]
}

@test "leftovers: a unit holding a folder find cannot read is in use, never partly removed" {
  local u="$HOME/.android/avd/Pixel.avd"
  unit "$u"
  mkdir -p "$u/locked"
  : >"$u/locked/live"
  find "$u" -exec touch -t 202001010000 {} +
  touch "$u/locked/live"
  chmod 000 "$u/locked"
  run_script "$LEFTOVERS" remove android-avd
  chmod 755 "$u/locked"
  [ "$status" -eq 0 ]
  [ -e "$u/data" ]
  [ "$(field .removed)" = '[]' ]
  field '.skipped[0].reason' | grep -qF 'in use'
}

@test "leftovers max: a runtime a device is booting or shutting down on is not deleted" {
  local id='00000000-0000-0000-0000-0000000000' state
  runtimes "{
    \"a\": {\"identifier\": \"${id}31\", \"runtimeIdentifier\": \"r1\", \"platformIdentifier\": \"p\", \"version\": \"1.0\", \"state\": \"Ready\", \"deletable\": true},
    \"b\": {\"identifier\": \"${id}32\", \"runtimeIdentifier\": \"r2\", \"platformIdentifier\": \"p\", \"version\": \"2.0\", \"state\": \"Ready\", \"deletable\": true}
  }"
  for state in Booting "Shutting Down"; do
    printf '{"devices": {"r1": [{"udid": "u", "state": "%s"}], "r2": []}}' "$state" >"$BATS_TEST_TMPDIR/dev.json"
    STUB_XCRUN_SIMCTL_LIST_DEVICES_J="$BATS_TEST_TMPDIR/dev.json" STUB_XCRUN=/dev/null run_script "$LEFTOVERS" remove --max simulator-runtimes
    [ "$status" -eq 0 ]
    [ "$(grep -c 'runtime delete' "$STUB_LOG")" = 0 ]
  done
}

@test "leftovers: a build folder holding a bare git repo is not a unit" {
  local r="$HOME/Projects/app"
  git init -q -b main "$r"
  printf 'dist/\n' >"$r/.gitignore"
  git init -q --bare "$r/dist/mirror.git"
  find "$r/dist" -exec touch -t 202001010000 {} +
  run_script "$LEFTOVERS" list
  [ "$status" -eq 0 ]
  [ "$(field '[.items[].id]')" = '[]' ]
}
