setup() {
  load helpers
  FREESPACE="$SCRIPTS_DIR/freespace.sh"
}

field() { printf '%s' "$output" | /usr/bin/jq -c "$1"; }

@test "freespace: target is 40+10+swap+caches" {
  run_script "$FREESPACE" --free 30 --swap 2 --caches 8
  [ "$status" -eq 0 ]
  [ "$(field .target_gb)" = 60 ]
  [ "$(field .gap_gb)" = 30 ]
  [ "$(field .free_gb)" = 30 ]
  [ "$(field .caches_unknown)" = false ]
  [ "$(field .formula)" = '"40+10+swap+caches (snapshots unknown, counted as 0)"' ]
}

@test "freespace: arguments in any order" {
  run_script "$FREESPACE" --caches 8 --free 30 --swap 2
  [ "$status" -eq 0 ]
  [ "$(field .target_gb)" = 60 ]
}

@test "freespace: caches unknown counted as 0" {
  run_script "$FREESPACE" --free 10 --swap 1 --caches unknown
  [ "$status" -eq 0 ]
  [ "$(field .target_gb)" = 51 ]
  [ "$(field .caches_unknown)" = true ]
}

@test "freespace: target rounded up, decimals accepted" {
  run_script "$FREESPACE" --free 12.5 --swap 1.07 --caches 0.01
  [ "$status" -eq 0 ]
  [ "$(field .target_gb)" = 52 ]
  [ "$(field .gap_gb)" = 39.5 ]
  [ "$(field .free_gb)" = 12.5 ]
}

@test "freespace: whole target not rounded further" {
  run_script "$FREESPACE" --free 0 --swap 0 --caches 0
  [ "$(field .target_gb)" = 50 ]
}

@test "freespace: gap never negative" {
  run_script "$FREESPACE" --free 81.06 --swap 1 --caches 2
  [ "$status" -eq 0 ]
  [ "$(field .target_gb)" = 53 ]
  [ "$(field .gap_gb)" = 0 ]
}

@test "freespace: missing argument exits 2" {
  for args in "--swap 1 --caches 1" "--free 1 --caches 1" "--free 1 --swap 1" "--free" ""; do
    # shellcheck disable=SC2086 # split on purpose
    run_script "$FREESPACE" $args
    [ "$status" -eq 2 ]
    [ -z "$output" ]
  done
}

@test "freespace: negative or non-numeric argument exits 2" {
  for bad in -1 abc 1.2.3 1e3 "" . 1. unknown; do
    run_script "$FREESPACE" --free "$bad" --swap 1 --caches 1
    [ "$status" -eq 2 ]
  done
  run_script "$FREESPACE" --free 1 --swap unknown --caches 1
  [ "$status" -eq 2 ]
  run_script "$FREESPACE" --free 1 --swap 1 --caches -2
  [ "$status" -eq 2 ]
}

@test "freespace: unknown option exits 2" {
  run_script "$FREESPACE" --free 1 --swap 1 --caches 1 --other 2
  [ "$status" -eq 2 ]
}

@test "freespace: missing jq exits 2" {
  DISKDIET_JQ="$BATS_TEST_TMPDIR/nojq" run_script "$FREESPACE" --free 1 --swap 1 --caches 1
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"jq"* ]]
}

@test "freespace: runs under 10 s" {
  local start=$SECONDS
  run_script "$FREESPACE" --free 1 --swap 1 --caches 1
  [ $((SECONDS - start)) -lt 10 ]
}
