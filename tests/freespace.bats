setup() {
  load helpers
  FREESPACE="$SCRIPTS_DIR/freespace.sh"
}

field() { printf '%s' "$output" | /usr/bin/jq -c "$1"; }

@test "freespace: target keeps the disk at most N% used" {
  run_script "$FREESPACE" --total 1000 --free 70 --max-used-pct 40
  [ "$status" -eq 0 ]
  [ "$(field .target_gb)" = 600 ]
  [ "$(field .gap_gb)" = 530 ]
  [ "$(field .free_gb)" = 70 ]
  [ "$(field .max_used_pct)" = 40 ]
  [ "$(field .formula)" = '"free >= total x (100 - 40)% (at most 40% used)"' ]
}

@test "freespace: arguments in any order" {
  run_script "$FREESPACE" --max-used-pct 40 --free 70 --total 1000
  [ "$status" -eq 0 ]
  [ "$(field .target_gb)" = 600 ]
}

@test "freespace: target rounded up, decimals accepted" {
  run_script "$FREESPACE" --total 926.3 --free 457.5 --max-used-pct 40
  [ "$status" -eq 0 ]
  [ "$(field .target_gb)" = 556 ]
  [ "$(field .gap_gb)" = 98.5 ]
}

@test "freespace: gap never negative" {
  run_script "$FREESPACE" --total 100 --free 90 --max-used-pct 40
  [ "$status" -eq 0 ]
  [ "$(field .target_gb)" = 60 ]
  [ "$(field .gap_gb)" = 0 ]
}

@test "freespace: missing argument exits 2" {
  for args in "--free 1 --max-used-pct 40" "--total 1 --max-used-pct 40" "--total 1 --free 1" "--free" ""; do
    # shellcheck disable=SC2086 # split on purpose
    run_script "$FREESPACE" $args
    [ "$status" -eq 2 ]
    [ -z "$output" ]
  done
}

@test "freespace: negative or non-numeric argument exits 2" {
  for bad in -1 abc 1.2.3 1e3 "" . 1. unknown; do
    run_script "$FREESPACE" --total 100 --free "$bad" --max-used-pct 40
    [ "$status" -eq 2 ]
  done
  run_script "$FREESPACE" --total -5 --free 1 --max-used-pct 40
  [ "$status" -eq 2 ]
}

@test "freespace: percent outside 1-99 exits 2" {
  for bad in 0 100 150 40.5; do
    run_script "$FREESPACE" --total 100 --free 1 --max-used-pct "$bad"
    [ "$status" -eq 2 ]
  done
}

@test "freespace: zero total exits 2" {
  run_script "$FREESPACE" --total 0 --free 0 --max-used-pct 40
  [ "$status" -eq 2 ]
}

@test "freespace: unknown option exits 2" {
  run_script "$FREESPACE" --total 100 --free 1 --max-used-pct 40 --swap 2
  [ "$status" -eq 2 ]
}

@test "freespace: missing jq exits 2" {
  DISKDIET_JQ="$BATS_TEST_TMPDIR/nojq" run_script "$FREESPACE" --total 100 --free 1 --max-used-pct 40
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"jq"* ]]
}

@test "freespace: runs under 10 s" {
  local start=$SECONDS
  run_script "$FREESPACE" --total 100 --free 1 --max-used-pct 40
  [ $((SECONDS - start)) -lt 10 ]
}

@test "freespace: more free space than the disk holds exits 2" {
  run_script "$FREESPACE" --total 100 --free 100.5 --max-used-pct 40
  [ "$status" -eq 2 ]
  run_script "$FREESPACE" --total 100 --free 100 --max-used-pct 40
  [ "$status" -eq 0 ]
}

@test "freespace: a size of 10 or more digits exits 2" {
  run_script "$FREESPACE" --total 1000000000 --free 1 --max-used-pct 40
  [ "$status" -eq 2 ]
  run_script "$FREESPACE" --total 100 --free 1234567890.5 --max-used-pct 40
  [ "$status" -eq 2 ]
  run_script "$FREESPACE" --total 999999999 --free 1 --max-used-pct 40
  [ "$status" -eq 0 ]
}
