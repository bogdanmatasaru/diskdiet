setup() {
  load helpers
}

@test "product scripts run on /bin/bash 3.2" {
  # shellcheck disable=SC2016 # expanded by the inner shell
  run "$SCRIPT_BASH" -c 'echo ${BASH_VERSINFO[0]}'
  [ "$status" -eq 0 ]
  if [ "$SCRIPT_BASH" = /bin/bash ]; then
    [ "$output" = "3" ]
  fi
}

@test "HOME is a temp folder" {
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]
}

@test "stub prints its fixture and logs argv" {
  stub_output diskutil sw_vers.txt
  run diskutil info -plist /
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$FIXTURES_DIR/sw_vers.txt")" ]
  [ "$(cat "$STUB_LOG")" = "diskutil info -plist /" ]
}

@test "stub picks the fixture for the exact argv first" {
  stub_output diskutil sw_vers.txt info disk0
  run diskutil info disk0
  [ "$output" = "$(cat "$FIXTURES_DIR/sw_vers.txt")" ]
  run diskutil apfs list
  [ "$status" -eq 1 ]
  [[ "$output" == *"no fixture set"* ]]
}

@test "run_script splits stdout and stderr" {
  run_script "$TESTS_DIR/smoke.sh" hello
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
  run_script "$TESTS_DIR/smoke.sh"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  [ "$stderr" = "usage: smoke.sh hello" ]
}
