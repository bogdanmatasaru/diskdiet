# Loaded from each test file's setup(). Gives every test a temp HOME, stubs
# first on PATH, a stub argv log, and $SCRIPT_BASH to run the product scripts.
# shellcheck disable=SC2034 # variables are read by the test files that load this

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS_DIR="$TESTS_DIR/../skills/diskdiet/scripts"
FIXTURES_DIR="$TESTS_DIR/fixtures"

# Product scripts target /bin/bash 3.2; only the kcov run overrides this.
SCRIPT_BASH="${SCRIPT_BASH:-/bin/bash}"

export HOME="$BATS_TEST_TMPDIR/home"
mkdir -p "$HOME"
export PATH="$TESTS_DIR/stubs:$PATH"
export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
: >"$STUB_LOG"
# Mole source for guard.sh: the fixture, unless a test clears it.
export DISKDIET_MOLE_LIB="$FIXTURES_DIR/mole-lib"

# stub_output <tool> <fixture> [args...]: the stubbed tool prints
# fixtures/<fixture>, for any argv or only for the given args.
stub_output() {
  local tool=$1 fixture=$2 key
  shift 2
  key=$(printf '%s' "$tool${*:+ $*}" | tr '[:lower:]' '[:upper:]' | tr -cs 'A-Z0-9' '_' | sed 's/^_*//; s/_*$//')
  export "STUB_$key=$FIXTURES_DIR/$fixture"
}

# run_script <path> [args...]: runs a product script on $SCRIPT_BASH and sets
# $status, $output (stdout) and $stderr. Scripts never run through their
# shebang, since kcov cannot trace /bin/bash 3.2; and not through bats `run`,
# which loses kcov traces when bats_require_minimum_version is set.
run_script() {
  status=0
  output=$("$SCRIPT_BASH" "$@" 2>"$BATS_TEST_TMPDIR/stderr") || status=$?
  stderr=$(cat "$BATS_TEST_TMPDIR/stderr")
}

# healthy: every tool answers with a captured, healthy fixture. The login items
# fixture is rewritten for the UID running the tests.
healthy() {
  stub_output df df.txt -k /System/Volumes/Data
  stub_output df df_root.txt -k /
  stub_output diskutil diskutil_info_root.plist info -plist /
  stub_output diskutil diskutil_info_disk0.txt info disk0
  stub_output diskutil diskutil_apfs_snapshots_data.txt apfs listSnapshots /System/Volumes/Data
  stub_output diskutil diskutil_apfs_snapshots_root.txt apfs listSnapshots /
  stub_output tmutil tmutil_snapshots_data.txt listlocalsnapshots /System/Volumes/Data
  stub_output tmutil tmutil_snapshots_root.txt listlocalsnapshots /
  stub_output memory_pressure memory_pressure.txt -Q
  stub_output sysctl sysctl_swapusage.txt vm.swapusage
  stub_output sysctl sysctl_hw_model.txt -n hw.model
  stub_output pmset pmset_therm.txt -g therm
  stub_output mdutil mdutil.txt -s /
  stub_output system_profiler system_profiler_power.json SPPowerDataType -json
  stub_output sw_vers sw_vers.txt
  sed "s/Records for UID 501 /Records for UID $(id -u) /" "$FIXTURES_DIR/sfltool_dumpbtm.txt" >"$BATS_TEST_TMPDIR/btm.txt"
  export STUB_SUDO_N_TRUE=/dev/null
  export STUB_SUDO_N_SFLTOOL_DUMPBTM="$BATS_TEST_TMPDIR/btm.txt"
}
