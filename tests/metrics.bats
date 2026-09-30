setup() {
  load helpers
  HOME=$(realpath "$HOME")
  METRICS="$SCRIPTS_DIR/metrics.sh"
  mkdir -p "$HOME/Library/Containers/com.a" "$HOME/Library/Containers/com.b" "$HOME/Pictures"
  healthy
}

teardown() {
  chmod -R u+rwx "$HOME" 2>/dev/null || true
}

field() { printf '%s' "$output" | /usr/bin/jq -c "$1"; }
unavailable() { field "[.unavailable[] | select(.field == \"$1\")] | length"; }

collect() {
  run_script "$METRICS" collect
  [ "$status" -eq 0 ]
}

total() {
  run_script "$METRICS" mole-total <"$FIXTURES_DIR/$1"
  [ "$status" -eq 0 ]
}

# metrics <name> [jq filter]: writes <name>.json, a healthy Metrics object with
# the filter applied.
metrics() {
  /usr/bin/jq -n --arg home "$HOME" '{free_gb: 83.06, used_gb: 836.96, total_gb: 994.61, used_pct: 91,
    container_free_gb: 83.06, snapshots: {count: 0, items: []}, swap_used_gb: 1.07, memory_free_pct: 39,
    smart: "Verified", thermal: {thermal_warning: false, performance_warning: false},
    spotlight: "Indexing enabled.", battery: {cycle_count: 67, condition: "Good", max_capacity_pct: 100},
    login_items: 4, protected: [{path: ($home + "/Library/Containers"), exists: true, items: 2}],
    machine: {model: "Mac", macos: "27.0", disk_total_gb: 994.61}, unavailable: []} | '"${2:-.}" \
    >"$BATS_TEST_TMPDIR/$1.json"
}

# evaluate: runs evaluate on before/after/target/stages, healthy by default.
evaluate() {
  local f
  for f in before after; do [ -f "$BATS_TEST_TMPDIR/$f.json" ] || metrics "$f"; done
  [ -f "$BATS_TEST_TMPDIR/target.json" ] || echo '{"target_gb":60,"gap_gb":0,"free_gb":83.06}' >"$BATS_TEST_TMPDIR/target.json"
  [ -f "$BATS_TEST_TMPDIR/stages.json" ] || echo '[]' >"$BATS_TEST_TMPDIR/stages.json"
  run_script "$METRICS" evaluate --before "$BATS_TEST_TMPDIR/before.json" --after "$BATS_TEST_TMPDIR/after.json" \
    --target "$BATS_TEST_TMPDIR/target.json" --stages "$BATS_TEST_TMPDIR/stages.json"
  [ "$status" -eq 0 ]
}

check() { field ".[] | select(.name == \"$1\") | .${2:-status}"; }

# status_is <check> <status> [after filter]: evaluate with the after filter.
status_is() {
  rm -f "$BATS_TEST_TMPDIR/after.json"
  metrics after "${3:-.}"
  evaluate
  [ "$(check "$1")" = "\"$2\"" ]
}

uninstalled() {
  echo '[{"name":"uninstall","answer":"'"${2:-yes}"'","apps":'"$1"'}]' >"$BATS_TEST_TMPDIR/stages.json"
}

# report [args...]: runs report on the evaluate inputs (healthy by default) into
# $BATS_TEST_TMPDIR/logs, then loads the written JSON into $output.
report() {
  local f
  for f in before after; do [ -f "$BATS_TEST_TMPDIR/$f.json" ] || metrics "$f"; done
  [ -f "$BATS_TEST_TMPDIR/target.json" ] || echo '{"target_gb":60,"gap_gb":0,"free_gb":83.06}' >"$BATS_TEST_TMPDIR/target.json"
  [ -f "$BATS_TEST_TMPDIR/stages.json" ] || echo '[]' >"$BATS_TEST_TMPDIR/stages.json"
  run_script "$METRICS" report --before "$BATS_TEST_TMPDIR/before.json" --after "${AFTER:-$BATS_TEST_TMPDIR/after.json}" \
    --target "$BATS_TEST_TMPDIR/target.json" --stages "$BATS_TEST_TMPDIR/stages.json" \
    --out "${OUT:-$BATS_TEST_TMPDIR/logs}" "$@"
  [ "$status" -eq 0 ] || return 1
  json=$output
  md=${json%.json}.md
}

# fails <command>...: the command must fail (a bare `!` never fails a bats test).
fails() { if "$@"; then return 1; fi; }

rfield() { /usr/bin/jq -c "$1" "$json"; }

md_has() { grep -qF -- "$1" "$md"; }

# old_report <name> <free_gb> [checks]: writes an earlier report into the logs.
old_report() {
  mkdir -p "$BATS_TEST_TMPDIR/logs"
  /usr/bin/jq -n --argjson free "$2" --argjson checks "${3:-[]}" '{schema: 1, metrics_before: {free_gb: 1},
    metrics_after: {free_gb: $free}, checks: $checks}' >"$BATS_TEST_TMPDIR/logs/$1.json"
}

# --- collect -------------------------------------------------------------

@test "collect: every Metrics field from healthy fixtures" {
  collect
  [ "$(field '.free_gb')" = 83.06 ]
  [ "$(field '.used_gb')" = 836.96 ]
  [ "$(field '.total_gb')" = 994.61 ]
  [ "$(field '.used_pct')" = 91 ]
  [ "$(field '.container_free_gb')" = 83.06 ]
  [ "$(field '.snapshots')" = '{"count":0,"items":[]}' ]
  [ "$(field '.swap_used_gb')" = 1.07 ]
  [ "$(field '.memory_free_pct')" = 39 ]
  [ "$(field '.smart')" = '"Verified"' ]
  [ "$(field '.thermal')" = '{"thermal_warning":false,"performance_warning":false}' ]
  [ "$(field '.spotlight')" = '"Indexing enabled."' ]
  [ "$(field '.battery')" = '{"cycle_count":67,"condition":"Good","max_capacity_pct":100}' ]
  [ "$(field '.login_items')" = 4 ]
  [ "$(field '.unavailable')" = '[]' ]
  [ "$(field '.machine')" = '{"model":"'"$(cat "$FIXTURES_DIR/sysctl_hw_model.txt")"'","macos":"27.0","disk_total_gb":994.61}' ]
}

@test "collect: space from the Data volume, never /" {
  collect
  [ "$(field '.used_gb')" = 836.96 ]
  grep -q '^df -k /System/Volumes/Data$' "$STUB_LOG"
  ! grep -q '^df -k /$' "$STUB_LOG" || false
}

@test "collect: low free space read as is" {
  stub_output df df_low.txt -k /System/Volumes/Data
  collect
  [ "$(field '.free_gb')" = 16.11 ]
  [ "$(field '.used_pct')" = 99 ]
}

@test "collect: one Time Machine snapshot with its purgeable flag" {
  stub_output tmutil tmutil_snapshots_data_one.txt listlocalsnapshots /System/Volumes/Data
  stub_output diskutil diskutil_apfs_snapshots_data_pinned.txt apfs listSnapshots /System/Volumes/Data
  collect
  [ "$(field '.snapshots')" = '{"count":1,"items":[{"name":"com.apple.TimeMachine.2026-09-01-120000.local","purgeable":false,"date":"2026-09-01-120000"}]}' ]
}

@test "collect: sealed system snapshot ignored, each snapshot flagged" {
  stub_output tmutil tmutil_snapshots_data_two.txt listlocalsnapshots /System/Volumes/Data
  stub_output diskutil diskutil_apfs_snapshots_data_mixed.txt apfs listSnapshots /System/Volumes/Data
  collect
  [ "$(field '.snapshots.count')" = 2 ]
  [ "$(field '[.snapshots.items[] | .purgeable]')" = '[false,true]' ]
  [[ "$output" != *com.apple.os.update* ]]
}

@test "collect: snapshot date only from a well-formed Time Machine name" {
  out=$(jq -nc --arg names $'com.apple.TimeMachine.2026-09-01-120000.local\ncom.apple.TimeMachine.2026-09-01-12000.local\ncom.apple.TimeMachine.2026-09-01-120000.local; rm x' --arg flags "" -f "$SCRIPTS_DIR/jq/snapshots.jq")
  [ "$(jq -c '[.items[].date]' <<<"$out")" = '["2026-09-01-120000",null,null]' ]
}

@test "collect: snapshot missing from diskutil has unknown purgeable flag" {
  stub_output tmutil tmutil_snapshots_data_one.txt listlocalsnapshots /System/Volumes/Data
  collect
  [ "$(field '.snapshots.items[0].purgeable')" = null ]
}

@test "collect: login items counted for the current UID, enabled login item, app or agent" {
  collect
  [ "$(field '.login_items')" = 4 ]
}

@test "collect: login items read directly when running as root" {
  local real_id
  real_id=$(command -v id)
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # shellcheck disable=SC2016 # expanded by the fake id
  printf '#!/bin/bash\nif [ "${1:-}" = -u ]; then echo 0; else exec %s "$@"; fi\n' "$real_id" >"$BATS_TEST_TMPDIR/bin/id"
  chmod +x "$BATS_TEST_TMPDIR/bin/id"
  stub_output sfltool sfltool_dumpbtm.txt dumpbtm
  unset STUB_SUDO_N_TRUE STUB_SUDO_N_SFLTOOL_DUMPBTM
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$METRICS" collect
  [ "$status" -eq 0 ]
  [ "$(field '.login_items')" = 1 ]
  ! grep -q '^sudo' "$STUB_LOG" || false
}

@test "collect: login items unavailable when they would need an admin dialog" {
  unset STUB_SUDO_N_TRUE
  collect
  [ "$(field '.login_items')" = null ]
  [ "$(field '.unavailable[] | select(.field == "login_items") | .reason')" = '"needs an admin dialog (no cached sudo)"' ]
  ! grep -q '^sfltool' "$STUB_LOG" || false
}

@test "collect: login items unavailable when the current UID has no records" {
  sed "s/Records for UID 501 /Records for UID 99999 /" "$FIXTURES_DIR/sfltool_dumpbtm.txt" >"$BATS_TEST_TMPDIR/btm.txt"
  collect
  [ "$(field '.login_items')" = null ]
  [ "$(unavailable login_items)" = 1 ]
}

@test "collect: protected lists built-ins with top-level item counts" {
  collect
  [ "$(field '.protected')" = '[{"path":"'"$HOME"'/Library/Containers","exists":true,"items":2}]' ]
}

@test "collect: one and two photos libraries" {
  mkdir -p "$HOME/Pictures/One.photoslibrary/originals"
  collect
  [ "$(field '[.protected[].path]')" = '["'"$HOME"'/Library/Containers","'"$HOME"'/Pictures/One.photoslibrary"]' ]
  [ "$(field '.protected[1].items')" = 1 ]
  mkdir -p "$HOME/Pictures/Two.photoslibrary"
  collect
  [ "$(field '[.protected[].items]')" = '[2,1,0]' ]
}

@test "collect: whitelist path listed, missing one counted as absent" {
  mkdir -p "$HOME/.config/mole" "$HOME/Keep"
  : >"$HOME/Keep/a"
  printf '%s\n' "$HOME/Keep" "$HOME/Gone" "$HOME/Glob*" >"$HOME/.config/mole/whitelist"
  collect
  [ "$(field '.protected[] | select(.path == "'"$HOME"'/Keep") | [.exists, .items]')" = '[true,1]' ]
  [ "$(field '.protected[] | select(.path == "'"$HOME"'/Gone") | [.exists, .items]')" = '[false,0]' ]
  [ "$(field '[.protected[] | select(.path | contains("*"))] | length')" = 0 ]
}

@test "collect: protected file counts as one item" {
  mkdir -p "$HOME/.config/mole"
  : >"$HOME/keep.txt"
  echo "$HOME/keep.txt" >"$HOME/.config/mole/whitelist"
  collect
  [ "$(field '.protected[] | select(.path == "'"$HOME"'/keep.txt") | .items')" = 1 ]
}

@test "collect: unreadable Pictures gives protected an unavailable entry" {
  mkdir -p "$HOME/Pictures/One.photoslibrary"
  chmod 000 "$HOME/Pictures"
  collect
  [ "$(field '.protected[] | select(.path == "'"$HOME"'/Pictures") | .items')" = null ]
  [ "$(field '.unavailable[] | select(.field == "protected") | .reason')" = '"'"$HOME"'/Pictures unreadable"' ]
}

@test "collect: protected never measured with du" {
  collect
  ! grep -q '^du' "$STUB_LOG" || false
}

@test "collect: guard failure makes protected unavailable" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/jq"
  chmod +x "$BATS_TEST_TMPDIR/bin/jq"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$METRICS" collect
  [ "$status" -eq 0 ]
  [ "$(field '.free_gb')" = 83.06 ]
  [ "$(field '.protected')" = null ]
  [ "$(unavailable protected)" = 1 ]
}

@test "collect: no battery gives battery null and no unavailable entry" {
  stub_output system_profiler system_profiler_power_desktop.json SPPowerDataType -json
  collect
  [ "$(field '.battery')" = null ]
  [ "$(unavailable battery)" = 0 ]
}

@test "collect: worn battery parsed" {
  stub_output system_profiler system_profiler_power_worn.json SPPowerDataType -json
  collect
  [ "$(field '.battery.condition')" = '"Service Recommended"' ]
  [ "$(field '.battery.max_capacity_pct')" = 65 ]
}

@test "collect: warnings, failing SMART, disabled Spotlight, high swap, low memory" {
  stub_output pmset pmset_therm_warning.txt -g therm
  stub_output diskutil diskutil_info_disk0_failing.txt info disk0
  stub_output mdutil mdutil_disabled.txt -s /
  stub_output sysctl sysctl_swapusage_high.txt vm.swapusage
  stub_output memory_pressure memory_pressure_low.txt -Q
  collect
  [ "$(field '.thermal')" = '{"thermal_warning":true,"performance_warning":false}' ]
  [ "$(field '.smart')" = '"Failing"' ]
  [ "$(field '.spotlight')" != '"Indexing enabled."' ]
  [ "$(field '.swap_used_gb > 8')" = true ]
  [ "$(field '.memory_free_pct')" = 8 ]
}

@test "collect: each failing tool gives its field null and an unavailable entry" {
  local pairs="df:free_gb diskutil_info_plist:container_free_gb diskutil_info_disk0:smart tmutil:snapshots diskutil_apfs:snapshots memory_pressure:memory_free_pct sysctl_swap:swap_used_gb pmset:thermal mdutil:spotlight system_profiler:battery sfltool:login_items"
  local pair tool fld
  for pair in $pairs; do
    healthy
    tool=${pair%%:*}
    fld=${pair#*:}
    case $tool in
      df) unset STUB_DF_K_SYSTEM_VOLUMES_DATA ;;
      diskutil_info_plist) unset STUB_DISKUTIL_INFO_PLIST ;;
      diskutil_info_disk0) unset STUB_DISKUTIL_INFO_DISK0 ;;
      diskutil_apfs) unset STUB_DISKUTIL_APFS_LISTSNAPSHOTS_SYSTEM_VOLUMES_DATA ;;
      tmutil) unset STUB_TMUTIL_LISTLOCALSNAPSHOTS_SYSTEM_VOLUMES_DATA ;;
      memory_pressure) unset STUB_MEMORY_PRESSURE_Q ;;
      sysctl_swap) unset STUB_SYSCTL_VM_SWAPUSAGE ;;
      pmset) unset STUB_PMSET_G_THERM ;;
      mdutil) unset STUB_MDUTIL_S ;;
      system_profiler) unset STUB_SYSTEM_PROFILER_SPPOWERDATATYPE_JSON ;;
      sfltool) unset STUB_SUDO_N_SFLTOOL_DUMPBTM ;;
    esac
    collect
    [ "$(field ".$fld")" = null ] || { echo "$tool: $fld not null" >&2; return 1; }
    [ "$(unavailable "$fld")" = 1 ] || { echo "$tool: no unavailable entry" >&2; return 1; }
  done
}

@test "collect: failing df leaves space fields and disk total null" {
  unset STUB_DF_K_SYSTEM_VOLUMES_DATA
  collect
  [ "$(field '[.free_gb, .used_gb, .total_gb, .used_pct, .machine.disk_total_gb]')" = '[null,null,null,null,null]' ]
}

@test "collect: unparsable output counts as unavailable" {
  printf 'garbage\n' >"$BATS_TEST_TMPDIR/garbage.txt"
  for var in STUB_DF_K_SYSTEM_VOLUMES_DATA STUB_MEMORY_PRESSURE_Q STUB_SYSCTL_VM_SWAPUSAGE STUB_DISKUTIL_INFO_PLIST STUB_DISKUTIL_INFO_DISK0 STUB_MDUTIL_S STUB_SYSTEM_PROFILER_SPPOWERDATATYPE_JSON STUB_PMSET_G_THERM; do
    healthy
    export "$var=$BATS_TEST_TMPDIR/garbage.txt"
    collect
    [ "$(field '.unavailable | length')" -ge 1 ] || { echo "$var accepted garbage" >&2; return 1; }
  done
}

@test "collect: swap reported in G converted" {
  printf 'vm.swapusage: total = 4.00G  used = 2.00G  free = 2.00G  (encrypted)\n' >"$BATS_TEST_TMPDIR/swap.txt"
  export STUB_SYSCTL_VM_SWAPUSAGE="$BATS_TEST_TMPDIR/swap.txt"
  collect
  [ "$(field '.swap_used_gb')" = 2.15 ]
}

@test "collect: unreadable model or macOS version reported as unknown" {
  unset STUB_SYSCTL_N_HW_MODEL
  printf 'ProductName: macOS\n' >"$BATS_TEST_TMPDIR/sw.txt"
  export STUB_SW_VERS="$BATS_TEST_TMPDIR/sw.txt"
  collect
  [ "$(field '[.machine.model, .machine.macos]')" = '["unknown","unknown"]' ]
  unset STUB_SW_VERS
  collect
  [ "$(field '.machine.macos')" = '"unknown"' ]
}

@test "collect: machine has no serial, UUID or user name" {
  collect
  [ "$(field '.machine | keys')" = '["disk_total_gb","macos","model"]' ]
  [[ "$output" != *"$(id -un)"* ]]
  [[ "$output" != *redacted* ]]
  ! printf '%s' "$output" | grep -Eq '[0-9A-F]{8}-[0-9A-F]{4}-' || false
}

@test "collect: jq called as /usr/bin/jq, not from PATH" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\necho "fake jq" >&2\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/jq"
  chmod +x "$BATS_TEST_TMPDIR/bin/jq"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_script "$METRICS" collect
  [ "$status" -eq 0 ]
  [ "$(field '.free_gb')" = 83.06 ]
}

@test "collect: missing jq exits 2" {
  DISKDIET_JQ="$BATS_TEST_TMPDIR/nojq" run_script "$METRICS" collect
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"jq"* ]]
}

@test "collect: runs under 10 s" {
  local start=$SECONDS
  collect
  [ $((SECONDS - start)) -lt 10 ]
}

@test "usage error exits 2" {
  run_script "$METRICS"
  [ "$status" -eq 2 ]
  run_script "$METRICS" nonsense
  [ "$status" -eq 2 ]
}

# --- mole-total ----------------------------------------------------------

@test "mole-total: purge Would free approximately" {
  total mo_purge_dry_run.txt
  [ "$output" = 0.01 ]
}

@test "mole-total: clean Potential space" {
  total mo_clean_dry_run.txt
  [ "$output" = 0 ]
}

@test "mole-total: clean At least form, colour codes stripped" {
  total mo_clean_dry_run_at_least.txt
  [ "$output" = 2.5 ]
}

@test "mole-total: every unit converted in base 10" {
  local line want
  for line in "Potential space: 512B:0" "Potential space: 1500KB | Items: 2:0" "Would free approximately: 250.0MB | Items: 1:0.25" "Potential space: 12.34GB | Items: 9:12.34"; do
    want=${line##*:}
    printf 'Dry run complete\n%s\n' "${line%:*}" >"$BATS_TEST_TMPDIR/in.txt"
    run_script "$METRICS" mole-total <"$BATS_TEST_TMPDIR/in.txt"
    [ "$output" = "$want" ] || { echo "$line gave $output" >&2; return 1; }
  done
}

@test "mole-total: changed format prints unknown" {
  total mo_clean_dry_run_changed.txt
  [ "$output" = unknown ]
}

@test "mole-total: empty input prints unknown" {
  run_script "$METRICS" mole-total </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = unknown ]
}

@test "mole-total: a file name that is not UTF-8 still reads the total" {
  printf 'Cleaning ~/Library/Caches/\377\376\n  Potential space: 1.20GB\n' >"$BATS_TEST_TMPDIR/in.txt"
  LC_ALL=en_US.UTF-8 run_script "$METRICS" mole-total <"$BATS_TEST_TMPDIR/in.txt"
  [ "$status" -eq 0 ]
  [ "$output" = 1.2 ]
}

# --- evaluate ------------------------------------------------------------

@test "evaluate: healthy metrics pass every check in order" {
  evaluate
  [ "$(field '[.[].name]')" = '["free_space","snapshots","ssd_smart","memory","thermal","spotlight","battery","protected_intact","login_items"]' ]
  [ "$(field '[.[].status] | unique')" = '["pass"]' ]
  [ "$(field '[.[] | keys] | unique')" = '[["name","reason","status","threshold","value"]]' ]
}

@test "evaluate: free_space boundaries 19.9 / 20 / target" {
  status_is free_space fail '.free_gb = 19.9'
  status_is free_space warn '.free_gb = 20'
  status_is free_space warn '.free_gb = 59.99'
  status_is free_space pass '.free_gb = 60'
  [ "$(check free_space value)" = 60 ]
  [ "$(check free_space threshold)" = '{"target_gb":60,"fail_below_gb":20}' ]
}

@test "evaluate: free_space unavailable names the df reason" {
  status_is free_space unavailable '.free_gb = null | .unavailable = [{field: "free_gb", reason: "df failed"}]'
  [ "$(check free_space reason)" = '"df failed"' ]
}

@test "evaluate: snapshots purgeable pass, non-purgeable warn named, null unavailable" {
  status_is snapshots pass '.snapshots = {count: 1, items: [{name: "s1", purgeable: true}]}'
  status_is snapshots warn '.snapshots = {count: 2, items: [{name: "s1", purgeable: true}, {name: "s2", purgeable: false}]}'
  [ "$(check snapshots value)" = '["s2"]' ]
  [[ "$(check snapshots reason)" == *s2* ]]
  status_is snapshots warn '.snapshots = {count: 1, items: [{name: "s3", purgeable: null}]}'
  status_is snapshots unavailable '.snapshots = null | .unavailable = [{field: "snapshots", reason: "diskutil failed"}]'
  [ "$(check snapshots reason)" = '"diskutil failed"' ]
}

@test "evaluate: ssd_smart Verified pass, other fail, Not Supported and missing unavailable" {
  status_is ssd_smart pass
  status_is ssd_smart fail '.smart = "Failing"'
  status_is ssd_smart unavailable '.smart = "Not Supported"'
  status_is ssd_smart unavailable '.smart = null | .unavailable = [{field: "smart", reason: "diskutil failed"}]'
  [ "$(check ssd_smart reason)" = '"diskutil failed"' ]
}

@test "evaluate: memory boundaries for free percentage and swap" {
  status_is memory pass '.memory_free_pct = 20 | .swap_used_gb = 8'
  status_is memory warn '.memory_free_pct = 19'
  status_is memory warn '.memory_free_pct = 10'
  status_is memory fail '.memory_free_pct = 9'
  status_is memory warn '.swap_used_gb = 8.01'
  status_is memory fail '.memory_free_pct = 9 | .swap_used_gb = 9'
  [ "$(check memory value)" = '{"free_pct":9,"swap_used_gb":9}' ]
  status_is memory unavailable '.swap_used_gb = null | .unavailable = [{field: "swap_used_gb", reason: "sysctl failed"}]'
  status_is memory unavailable '.memory_free_pct = null'
}

@test "evaluate: thermal warning of either kind warns, null unavailable" {
  status_is thermal pass
  status_is thermal warn '.thermal.thermal_warning = true'
  status_is thermal warn '.thermal.performance_warning = true'
  status_is thermal unavailable '.thermal = null'
}

@test "evaluate: spotlight enabled pass, anything else warn, null unavailable" {
  status_is spotlight pass
  status_is spotlight warn '.spotlight = "Indexing disabled."'
  status_is spotlight unavailable '.spotlight = null'
}

@test "evaluate: battery boundaries and conditions" {
  status_is battery pass '.battery.max_capacity_pct = 80'
  status_is battery pass '.battery.condition = "Normal"'
  status_is battery warn '.battery.max_capacity_pct = 79'
  status_is battery warn '.battery.max_capacity_pct = 70'
  status_is battery fail '.battery.max_capacity_pct = 69'
  status_is battery warn '.battery.condition = "Service Recommended"'
  status_is battery unavailable '.battery.max_capacity_pct = null'
}

@test "evaluate: no battery is not_applicable, unreadable battery unavailable" {
  status_is battery not_applicable '.battery = null'
  status_is battery unavailable '.battery = null | .unavailable = [{field: "battery", reason: "system_profiler failed"}]'
  [ "$(check battery reason)" = '"system_profiler failed"' ]
}

@test "evaluate: login_items 30 pass, 31 warn, null unavailable with reason" {
  status_is login_items pass '.login_items = 30'
  status_is login_items warn '.login_items = 31'
  status_is login_items unavailable '.login_items = null | .unavailable = [{field: "login_items", reason: "needs an admin dialog (no cached sudo)"}]'
  [ "$(check login_items reason)" = '"needs an admin dialog (no cached sudo)"' ]
}

@test "evaluate: protected intact with same or higher counts passes" {
  status_is protected_intact pass '.protected[0].items = 3'
}

@test "evaluate: protected path gone fails, named" {
  metrics before '.protected += [{path: "/w/Keep", exists: true, items: 1}]'
  status_is protected_intact fail '.protected += [{path: "/w/Keep", exists: false, items: 0}]'
  [[ "$(check protected_intact reason)" == */w/Keep* ]]
}

@test "evaluate: built-in Containers or Photos library dropped fails, named" {
  status_is protected_intact fail '.protected[0].items = 1'
  [[ "$(check protected_intact reason)" == *"$HOME/Library/Containers"* ]]
  # shellcheck disable=SC2016 # $home is a jq variable
  metrics before '.protected += [{path: ($home + "/Pictures/P.photoslibrary"), exists: true, items: 5}]'
  # shellcheck disable=SC2016 # $home is a jq variable
  status_is protected_intact fail '.protected += [{path: ($home + "/Pictures/P.photoslibrary"), exists: true, items: 4}]'
  [[ "$(check protected_intact reason)" == *P.photoslibrary* ]]
}

@test "evaluate: whitelist-only count dropped warns, named" {
  metrics before '.protected += [{path: "/w/Keep", exists: true, items: 3}]'
  status_is protected_intact warn '.protected += [{path: "/w/Keep", exists: true, items: 2}]'
  [[ "$(check protected_intact reason)" == */w/Keep* ]]
}

@test "evaluate: Containers dropped only by uninstalled app containers passes" {
  metrics before '.protected[0].items = 4'
  uninstalled '["com.app","com.app.ext"]'
  status_is protected_intact pass '.protected[0].items = 2'
  status_is protected_intact fail '.protected[0].items = 1'
  uninstalled '["com.app","com.app.ext"]' no
  status_is protected_intact fail '.protected[0].items = 2'
}

@test "evaluate: protected items null before or after is unavailable, never pass" {
  metrics before '.protected += [{path: "/w/Secret", exists: true, items: null}]'
  status_is protected_intact unavailable '.protected += [{path: "/w/Secret", exists: true, items: 1}]'
  [[ "$(check protected_intact reason)" == */w/Secret* ]]
  metrics before '.protected += [{path: "/w/Secret", exists: true, items: 1}]'
  status_is protected_intact unavailable '.protected += [{path: "/w/Secret", exists: true, items: null}]'
  [[ "$(check protected_intact reason)" == */w/Secret* ]]
  status_is protected_intact unavailable '.protected = null | .unavailable = [{field: "protected", reason: "guard.sh list failed"}]'
  [ "$(check protected_intact reason)" = '"guard.sh list failed"' ]
}

@test "evaluate: protected path missing from after is unavailable" {
  metrics before '.protected += [{path: "/w/Keep", exists: true, items: 1}]'
  status_is protected_intact unavailable
  [[ "$(check protected_intact reason)" == */w/Keep* ]]
}

@test "evaluate: glob and sentinel whitelist lines ignored end to end" {
  mkdir -p "$HOME/.config/mole" "$HOME/Keep"
  : >"$HOME/Keep/a"
  printf '%s\n' "$HOME/Keep" "$HOME/Glob*" FINDER_METADATA >"$HOME/.config/mole/whitelist"
  collect
  printf '%s' "$output" >"$BATS_TEST_TMPDIR/before.json"
  printf '%s' "$output" >"$BATS_TEST_TMPDIR/after.json"
  evaluate
  [ "$(check protected_intact)" = '"pass"' ]
  [ "$(check protected_intact value)" = '[]' ]
}

@test "evaluate: missing or unreadable input exits 2" {
  run_script "$METRICS" evaluate --before x
  [ "$status" -eq 2 ]
  echo '{' >"$BATS_TEST_TMPDIR/stages.json"
  run_script "$METRICS" evaluate --before "$BATS_TEST_TMPDIR/none.json" --after x --target x --stages x
  [ "$status" -eq 2 ]
  metrics before
  metrics after
  echo '{"target_gb":60}' >"$BATS_TEST_TMPDIR/target.json"
  run_script "$METRICS" evaluate --before "$BATS_TEST_TMPDIR/before.json" --after "$BATS_TEST_TMPDIR/after.json" \
    --target "$BATS_TEST_TMPDIR/target.json" --stages "$BATS_TEST_TMPDIR/stages.json"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *evaluate* ]]
  echo '{}' >"$BATS_TEST_TMPDIR/stages.json"
  run_script "$METRICS" evaluate --before "$BATS_TEST_TMPDIR/before.json" --after "$BATS_TEST_TMPDIR/after.json" \
    --target "$BATS_TEST_TMPDIR/target.json" --stages "$BATS_TEST_TMPDIR/stages.json"
  [ "$status" -eq 2 ]
  run_script "$METRICS" evaluate --bogus x
  [ "$status" -eq 2 ]
}

@test "evaluate: runs under 10 s" {
  local start=$SECONDS
  evaluate
  [ $((SECONDS - start)) -lt 10 ]
}

# --- report ---------------------------------------------------------------

@test "report: writes stamped JSON and Markdown into a new out folder, prints the JSON path" {
  report
  [[ "$json" == "$BATS_TEST_TMPDIR/logs/"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].json ]]
  [ -f "$md" ]
  [ "$(find "$BATS_TEST_TMPDIR/logs" -type f | wc -l | tr -d ' ')" = 2 ]
}

@test "report: JSON has the schema's required keys and enums" {
  echo '[{"name":"analyse","answer":"not_applicable"},{"name":"clean","answer":"yes","preview_gb":3.2,"freed_gb":3.1,"errors":[]}]' \
    >"$BATS_TEST_TMPDIR/stages.json"
  report
  [ "$(rfield '[.schema, (.started_at | type), (.finished_at | type)]')" = '[1,"string","string"]' ]
  [ "$(rfield '.started_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$")')" = true ]
  [ "$(rfield '.machine')" = '{"model":"Mac","macos":"27.0","disk_total_gb":994.61}' ]
  [ "$(rfield '[.metrics_before, .metrics_after] | map(type)')" = '["object","object"]' ]
  [ "$(rfield '.target | [.target_gb, .gap_gb, .free_gb] | map(type)')" = '["number","number","number"]' ]
  [ "$(rfield '[.stages[].name] - ["analyse","clean","snapshots","large_files","uninstall","optimize"]')" = '[]' ]
  [ "$(rfield '[.stages[].answer] - ["yes","no","skipped","not_applicable"]')" = '[]' ]
  [ "$(rfield '[.checks[].name]')" = '["free_space","snapshots","ssd_smart","memory","thermal","spotlight","battery","protected_intact","login_items"]' ]
  [ "$(rfield '[.checks[].status] - ["pass","warn","fail","unavailable","not_applicable"]')" = '[]' ]
  [ "$(rfield 'has("previous")')" = true ]
}

@test "report: target free space and gap taken from after" {
  metrics after '.free_gb = 50'
  report
  [ "$(rfield '.target')" = '{"target_gb":60,"gap_gb":10,"free_gb":50}' ]
}

@test "report: after - gives metrics_after null, no checks, target from before" {
  metrics before '.free_gb = 30'
  AFTER=- report
  [ "$(rfield '.metrics_after')" = null ]
  [ "$(rfield '.checks')" = '[]' ]
  [ "$(rfield '.target | [.free_gb, .gap_gb]')" = '[30,30]' ]
  md_has "Sanity checks not run"
}

@test "report: without --previous the newest JSON in out is the previous run" {
  old_report 2020-01-01-000000 10
  old_report 2020-06-01-000000 40
  report
  [ "$(rfield '.previous | [.file, .free_gb, .delta_free_gb]')" = "[\"$BATS_TEST_TMPDIR/logs/2020-06-01-000000.json\",40,43.06]" ]
}

@test "report: --previous gives free space, difference and changed check names" {
  old_report 2020-01-01-000000 90 '[{"name":"free_space","status":"pass"},{"name":"memory","status":"warn"},{"name":"thermal","status":"pass"}]'
  old_report 2021-01-01-000000 1
  metrics after '.thermal.thermal_warning = true'
  report --previous "$BATS_TEST_TMPDIR/logs/2020-01-01-000000.json"
  [ "$(rfield '.previous | [.free_gb, .delta_free_gb]')" = '[90,-6.94]' ]
  [ "$(rfield '.previous.checks.changed')" = '["memory","thermal"]' ]
  [ "$(rfield '.previous.checks.status.memory')" = '"warn"' ]
  [ "$(rfield 'has("previous_reason")')" = false ]
  md_has "| memory | pass | warn |"
  md_has "-6.94"
}

@test "report: previous without after uses its before free space" {
  mkdir -p "$BATS_TEST_TMPDIR/logs"
  echo '{"schema":1,"metrics_before":{"free_gb":80},"metrics_after":null,"checks":[]}' >"$BATS_TEST_TMPDIR/logs/2020-01-01-000000.json"
  report
  [ "$(rfield '.previous | [.free_gb, .delta_free_gb]')" = '[80,3.06]' ]
}

@test "report: no earlier report gives previous null with a reason" {
  report
  [ "$(rfield '.previous')" = null ]
  [[ "$(rfield '.previous_reason')" == *"no previous report"* ]]
  md_has "No baseline"
}

@test "report: missing or corrupt previous gives previous null with a reason, still completes" {
  report --previous "$BATS_TEST_TMPDIR/none.json"
  [ "$(rfield '.previous')" = null ]
  [[ "$(rfield '.previous_reason')" == *none.json* ]]
  echo '{' >"$BATS_TEST_TMPDIR/bad.json"
  report --previous "$BATS_TEST_TMPDIR/bad.json"
  [ "$(rfield '.previous')" = null ]
  [[ "$(rfield '.previous_reason')" == *bad.json* ]]
  echo '[1]' >"$BATS_TEST_TMPDIR/bad.json"
  report --previous "$BATS_TEST_TMPDIR/bad.json"
  [ "$(rfield '.previous')" = null ]
  md_has "No baseline"
}

@test "report: malformed stages exits 2 with the parse error, writes nothing" {
  echo '[{' >"$BATS_TEST_TMPDIR/stages.json"
  fails report
  [ "$status" -eq 2 ]
  [[ "$stderr" == *stages.json* ]]
  [ ! -e "$BATS_TEST_TMPDIR/logs" ] || [ -z "$(ls "$BATS_TEST_TMPDIR/logs")" ]
  echo '{}' >"$BATS_TEST_TMPDIR/stages.json"
  fails report
  [ "$status" -eq 2 ]
  AFTER=- fails report
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"stages.json is not a JSON array"* ]]
}

@test "report: missing argument or unreadable metrics exits 2" {
  run_script "$METRICS" report --before x
  [ "$status" -eq 2 ]
  run_script "$METRICS" report --bogus x
  [ "$status" -eq 2 ]
  run_script "$METRICS" report --before a --after b --target c --stages d
  [ "$status" -eq 2 ]
  echo nope >"$BATS_TEST_TMPDIR/before.json"
  fails report
  [ "$status" -eq 2 ]
  AFTER=- fails report
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed input"* ]]
}

@test "report: unreadable after free space keeps the given target" {
  metrics after '.free_gb = null'
  report
  [ "$(rfield '.target')" = '{"target_gb":60,"gap_gb":0,"free_gb":83.06}' ]
}

@test "report: previous without free space or checks gives an unknown difference" {
  mkdir -p "$BATS_TEST_TMPDIR/logs"
  echo '{"schema":1,"metrics_before":{},"metrics_after":null}' >"$BATS_TEST_TMPDIR/logs/2020-01-01-000000.json"
  report
  [ "$(rfield '.previous | [.free_gb, .delta_free_gb, .checks.changed]')" = '[null,null,[]]' ]
  md_has "| Free space | unknown | 83.06 GB | 83.06 GB | 0 GB | unknown |"
}

@test "report: write failure exits non-zero with a message" {
  mkdir -p "$BATS_TEST_TMPDIR/logs"
  chmod 555 "$BATS_TEST_TMPDIR/logs"
  fails report
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"cannot write"* ]]
  touch "$BATS_TEST_TMPDIR/file"
  OUT="$BATS_TEST_TMPDIR/file" fails report
  [[ "$stderr" == *"cannot write"* ]]
}

@test "report: Markdown has summary, space, stages, checks and blockers sections" {
  report
  for s in "# diskdiet report" "## Summary" "## Space" "## Stages" "## Checks" "## What still blocks the target"; do md_has "$s"; done
  md_has "| free_space | pass |"
  md_has "Target met"
}

@test "report: Markdown states snapshot size as unknown" {
  report
  md_has "Snapshot size is unknown"
}

@test "report: Markdown names what still blocks the target" {
  metrics after '.free_gb = 45 | .snapshots = {count: 1, items: [{name: "com.apple.TimeMachine.2026-09-29-100000.local", purgeable: false}]}'
  echo '[{"name":"clean","answer":"no","preview_gb":4.5},{"name":"snapshots","answer":"yes","recreated":["com.apple.TimeMachine.y.local"]},{"name":"large_files","answer":"not_applicable","preview_gb":20},{"name":"uninstall","answer":"skipped","preview_gb":null}]' \
    >"$BATS_TEST_TMPDIR/stages.json"
  report
  md_has "15 GB short of the 60 GB target"
  md_has "clean: answered no (4.5 GB previewed)"
  md_has "uninstall: skipped"
  md_has "snapshot com.apple.TimeMachine.2026-09-29-100000.local is not purgeable"
  md_has "snapshots recreated after deletion: com.apple.TimeMachine.y.local"
  fails md_has "large_files: "
}

@test "report: zero snapshots shows the snapshot stage as skipped" {
  echo '[{"name":"snapshots","answer":"not_applicable","preview_items":0}]' >"$BATS_TEST_TMPDIR/stages.json"
  report
  md_has "| snapshots | skipped (no snapshots) |"
}

@test "report: recreated snapshots and stage errors reported" {
  echo '[{"name":"snapshots","answer":"yes","preview_items":2,"recreated":["com.apple.TimeMachine.x.local"],"errors":["tmutil: busy","a|b"]},{"name":"uninstall","answer":"yes","freed_gb":2}]' \
    >"$BATS_TEST_TMPDIR/stages.json"
  report
  md_has "recreated: com.apple.TimeMachine.x.local"
  md_has "errors: tmutil: busy; a\\|b"
  md_has "in the Trash"
}

@test "report: Markdown complete when before or after free space is unknown" {
  metrics after '.free_gb = null'
  report
  md_has "| Free space | unknown | 83.06 GB | unknown | unknown | unknown |"
  md_has "## What still blocks the target"
  metrics before '.free_gb = null'
  metrics after
  report
  md_has "| Free space | unknown | unknown | 83.06 GB | unknown | unknown |"
  md_has "## What still blocks the target"
}

@test "report: stage notes that are not lists still render" {
  echo '[{"name":"clean","answer":"yes","errors":"mo clean failed","recreated":null}]' >"$BATS_TEST_TMPDIR/stages.json"
  report
  md_has "errors: mo clean failed"
  md_has "## What still blocks the target"
}

@test "report: Markdown render failure exits 2 and writes nothing" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\ncase "$*" in *report-md.jq*) exit 5 ;; esac\nexec /usr/bin/jq "$@"\n' >"$BATS_TEST_TMPDIR/bin/jq"
  chmod +x "$BATS_TEST_TMPDIR/bin/jq"
  DISKDIET_JQ="$BATS_TEST_TMPDIR/bin/jq" fails report
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"cannot render"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/logs" ] || [ -z "$(ls -A "$BATS_TEST_TMPDIR/logs")" ]
}

@test "report: runs under 10 s" {
  local start=$SECONDS
  report
  [ $((SECONDS - start)) -lt 10 ]
}

# --- save --------------------------------------------------------------------

# run_dir: a run folder as the skill makes it, under a test TMPDIR.
run_dir() {
  export TMPDIR="$BATS_TEST_TMPDIR/t"
  mkdir -p "$TMPDIR"
  RUN=$(mktemp -d "$TMPDIR/diskdiet-XXXXXX")
}

@test "save: writes stdin into a file of the run folder" {
  run_dir
  run_script "$METRICS" save "$RUN/before.json" <<<'{"a":1}'
  [ "$status" -eq 0 ]
  [ "$(cat "$RUN/before.json")" = '{"a":1}' ]
  run_script "$METRICS" save "$RUN/before.json" <<<'[2]'
  [ "$(cat "$RUN/before.json")" = '[2]' ]
  [ "$(ls "$RUN")" = before.json ]
}

@test "save: refuses any file outside a run folder under TMPDIR" {
  run_dir
  mkdir -p "$TMPDIR/other" "$HOME/diskdiet-abcdef" "$RUN/sub"
  ln -s "$HOME/diskdiet-abcdef" "$TMPDIR/diskdiet-linkdd"
  ln -s "$HOME/.zshrc" "$RUN/link.json"
  for f in "$TMPDIR/other/x.json" "$HOME/diskdiet-abcdef/x.json" "$TMPDIR/diskdiet-linkdd/x.json" \
    "$RUN/sub/x.json" "$RUN/../x.json" "$RUN/.hidden" "$RUN/link.json" "$RUN/a b.json" "$TMPDIR/diskdiet-nothere/x.json" x.json; do
    run_script "$METRICS" save "$f" <<<'{}'
    [ "$status" -eq 2 ] || { echo "not refused: $f" >&2; return 1; }
    [[ "$stderr" == *"save: not a file in a diskdiet run folder"* ]]
  done
  [ ! -e "$HOME/diskdiet-abcdef/x.json" ] && [ ! -e "$TMPDIR/x.json" ] && [ ! -e "$HOME/.zshrc" ]
}

@test "save: empty input exits 2 and writes nothing" {
  run_dir
  run_script "$METRICS" save "$RUN/analyze.json" </dev/null
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"save: no input"* ]]
  [ ! -e "$RUN/analyze.json" ]
}

@test "save: a planted temp-name symlink is never followed" {
  run_dir
  echo original >"$HOME/victim"
  ln -s "$HOME/victim" "$RUN/stages.json.tmp"
  run_script "$METRICS" save "$RUN/stages.json" <<<'[1]'
  [ "$(cat "$HOME/victim")" = original ]
  [ ! -L "$RUN/stages.json" ]
}

@test "save: run folder swapped for a symlink while stdin is open writes nothing" {
  run_dir
  mkdir "$HOME/elsewhere"
  { sleep 2 && echo '[1]'; } | "$SCRIPT_BASH" "$METRICS" save "$RUN/stages.json" 2>/dev/null &
  sleep 1
  mv "$RUN" "$TMPDIR/moved"
  ln -s "$HOME/elsewhere" "$RUN"
  wait "$!" || true
  [ -z "$(ls -A "$HOME/elsewhere")" ]
}

@test "save: concurrent saves to one file all succeed" {
  local i
  run_dir
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    { head -c 100000 /dev/zero | tr '\0' x | "$SCRIPT_BASH" "$METRICS" save "$RUN/big.txt" || echo "$i" >>"$BATS_TEST_TMPDIR/failed"; } 2>/dev/null &
  done
  wait
  [ ! -e "$BATS_TEST_TMPDIR/failed" ]
  [ "$(ls "$RUN")" = big.txt ]
}

@test "save: exactly one path" {
  run_dir
  run_script "$METRICS" save <<<'{}'
  [ "$status" -eq 2 ]
  run_script "$METRICS" save "$RUN/a.json" "$RUN/b.json" <<<'{}'
  [ "$status" -eq 2 ]
}
