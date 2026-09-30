#!/bin/bash
# Collects disk and health metrics as JSON and reads Mole dry-run totals.
# shellcheck disable=SC2016 # $name in jq programs is a jq variable
set -euo pipefail

JQ=${DISKDIET_JQ:-/usr/bin/jq}
DATA=/System/Volumes/Data
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TAB=$'\t'
NL=$'\n'

usage() {
  echo "usage: metrics.sh collect | mole-total | evaluate --before B --after A --target T --stages S" >&2
  echo "       metrics.sh report --before B --after A|- --target T --stages S [--previous P] --out DIR" >&2
  echo "       metrics.sh save RUN/<file> < content" >&2
  exit 2
}

int() {
  case $1 in
    "" | *[!0-9]*) return 1 ;;
  esac
}

number() {
  case $1 in
    "" | *[!0-9.]* | .* | *. | *.*.*) return 1 ;;
  esac
}

# unavailable <fields> <reason>: records each field as unreadable.
unavailable=""
unavailable() {
  local f
  for f in $1; do unavailable+="$f$TAB$2$NL"; done
}

# tool <fields> <command>...: sets $out to the command's stdout, or records the
# fields as unavailable and fails.
out=""
tool() {
  local fields=$1
  shift
  out=$("$@" 2>/dev/null) && return 0
  unavailable "$fields" "$1 failed"
  return 1
}

unrecognised() {
  unavailable "$1" "$2 output not recognised"
}

space() {
  local total used avail pct
  tool "free_gb used_gb total_gb used_pct" df -k "$DATA" || return 0
  read -r total used avail pct <<<"$(awk 'NR == 2 { sub(/%$/, "", $5); print $2, $3, $4, $5 }' <<<"$out")"
  if int "$total" && int "$used" && int "$avail" && int "$pct"; then
    space_kb="[$total,$used,$avail,$pct]"
  else
    unrecognised "free_gb used_gb total_gb used_pct" df
  fi
}

container_free() {
  local bytes
  tool container_free_gb diskutil info -plist / || return 0
  bytes=$(plutil -extract APFSContainerFree raw -o - - 2>/dev/null <<<"$out") || bytes=""
  if int "$bytes"; then container_bytes=$bytes; else unrecognised container_free_gb diskutil; fi
}

# Time Machine snapshots on the Data volume, flagged from diskutil. The sealed
# system snapshot lives on the system volume and never matches the prefix.
snapshots() {
  local names
  tool snapshots tmutil listlocalsnapshots "$DATA" || return 0
  names=$(awk '/^com\.apple\.TimeMachine\./' <<<"$out")
  tool snapshots diskutil apfs listSnapshots "$DATA" || return 0
  snapshots=$("$JQ" -nc --arg names "$names" --arg flags "$(awk '{ for (i = 1; i < NF; i++) { if ($i == "Name:") n = $(i + 1); if ($i == "Purgeable:") print n, $(i + 1) } }' <<<"$out")" -f "$SCRIPT_DIR/jq/snapshots.jq")
}

memory() {
  local pct
  tool memory_free_pct memory_pressure -Q || return 0
  pct=$(awk -F': ' '/memory free percentage/ { sub(/%$/, "", $2); print $2 }' <<<"$out")
  if int "$pct"; then memory_pct=$pct; else unrecognised memory_free_pct memory_pressure; fi
}

swap() {
  local used unit
  tool swap_used_gb sysctl vm.swapusage || return 0
  read -r used unit <<<"$(sed -n 's/.*used = \([0-9.]*\)\([MG]\).*/\1 \2/p' <<<"$out")"
  if number "$used"; then
    case $unit in
      M) swap_bytes="[$used,1048576]" ;;
      G) swap_bytes="[$used,1073741824]" ;;
    esac
  else
    unrecognised swap_used_gb sysctl
  fi
}

smart() {
  tool smart diskutil info disk0 || return 0
  smart=$(sed -n 's/^ *SMART Status: *//p' <<<"$out" | sed 's/ *$//')
  if [ -z "$smart" ]; then unrecognised smart diskutil; fi
}

thermal() {
  tool thermal pmset -g therm || return 0
  case $out in
    *"warning level"*) thermal=$("$JQ" -nc --arg t "$out" -f "$SCRIPT_DIR/jq/thermal.jq") ;;
    *) unrecognised thermal pmset ;;
  esac
}

spotlight() {
  tool spotlight mdutil -s / || return 0
  spotlight=$(awk 'NR == 2 { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print }' <<<"$out")
  if [ -z "$spotlight" ]; then unrecognised spotlight mdutil; fi
}

# No battery section (a desktop Mac) is null without an unavailable entry.
battery() {
  tool battery system_profiler SPPowerDataType -json || return 0
  battery=$("$JQ" -c -f "$SCRIPT_DIR/jq/battery.jq" 2>/dev/null <<<"$out") || {
    battery=null
    unrecognised battery system_profiler
  }
}

# Login items: enabled login item, app or agent records for this UID. sfltool
# raises an admin dialog unless it runs as root (research.md R6), so it runs
# only as root or through an already cached sudo.
login_items() {
  local uid n
  uid=$(id -u)
  if [ "$uid" = 0 ]; then
    tool login_items sfltool dumpbtm || return 0
  elif sudo -n true >/dev/null 2>&1; then
    tool login_items sudo -n sfltool dumpbtm || return 0
  else
    unavailable login_items "needs an admin dialog (no cached sudo)"
    return 0
  fi
  n=$(awk -v uid="$uid" -f "$SCRIPT_DIR/login_items.awk" <<<"$out")
  if int "$n"; then login_items=$n; else unrecognised login_items sfltool; fi
}

# Protected locations from guard.sh, each with its top-level item count (never
# du: sizes of a Photos library take minutes and are not needed).
protected() {
  local list p listing exists items rows=""
  if ! list=$("$BASH" "$SCRIPT_DIR/guard.sh" list 2>/dev/null); then
    unavailable protected "guard.sh list failed"
    return 0
  fi
  while IFS= read -r p; do
    exists=true
    if [ -d "$p" ]; then
      if listing=$(ls -A "$p" 2>/dev/null); then
        items=$(grep -c . <<<"$listing" || true)
      else
        items=null
        unavailable protected "$p unreadable"
      fi
    elif [ -e "$p" ]; then
      items=1
    else
      exists=false
      items=0
    fi
    rows+="$p$TAB$exists$TAB$items$NL"
  done <<<"$("$JQ" -r '.[]' <<<"$list")"
  protected=$("$JQ" -nc --arg rows "$rows" -f "$SCRIPT_DIR/jq/protected.jq")
}

machine() {
  model=unknown
  macos=unknown
  if out=$(sysctl -n hw.model 2>/dev/null) && [ -n "$out" ]; then model=$out; fi
  if out=$(sw_vers 2>/dev/null); then
    out=$(awk '/^ProductVersion:/ { print $2 }' <<<"$out")
    if [ -n "$out" ]; then macos=$out; fi
  fi
}

collect() {
  space_kb=null container_bytes=null snapshots=null memory_pct=null swap_bytes=null
  smart="" thermal=null spotlight="" battery=null login_items=null protected=null
  space
  container_free
  snapshots
  memory
  swap
  smart
  thermal
  spotlight
  battery
  login_items
  protected
  machine
  "$JQ" -nc \
    --argjson space "$space_kb" --argjson container "$container_bytes" --argjson snapshots "$snapshots" \
    --argjson memory "$memory_pct" --argjson swap "$swap_bytes" --arg smart "$smart" \
    --argjson thermal "$thermal" --arg spotlight "$spotlight" --argjson battery "$battery" \
    --argjson login "$login_items" --argjson protected "$protected" \
    --arg model "$model" --arg macos "$macos" --arg unavailable "$unavailable" -f "$SCRIPT_DIR/jq/collect.jq"
}

# The summary total of a `mo clean` or `mo purge` dry run in GB (base 10, as
# Mole prints), or `unknown` when no known summary line matches. Bytes (C
# locale), since file names in the output need not be UTF-8.
mole_total() {
  local size n unit scale
  local purge='s/.*Would free approximately: *\([0-9.]*[KMG]*B\).*/\1/p' clean='s/.*Potential space: *\(At least \)*\([0-9.]*[KMG]*B\).*/\2/p'
  size=$(LC_ALL=C sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=C sed -n -e "$purge" -e "$clean" | tail -1)
  n=${size%%[KMG]*}
  n=${n%B}
  unit=${size#"$n"}
  if ! number "$n"; then
    echo unknown
    return 0
  fi
  case $unit in
    B) scale=1 ;;
    KB) scale=1e3 ;;
    MB) scale=1e6 ;;
    GB) scale=1e9 ;;
  esac
  "$JQ" -n --argjson n "$n" --argjson scale "$scale" '$n * $scale / 1e9 * 100 | round / 100'
}

# CheckResult[] from before/after Metrics, the Target and the StageResult[],
# with the thresholds of contracts/cli.md § Checks.
evaluate() {
  local before="" after="" target="" stages="" home
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --before) before=$2 ;;
      --after) after=$2 ;;
      --target) target=$2 ;;
      --stages) stages=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  [ -n "$before" ] && [ -n "$after" ] && [ -n "$target" ] && [ -n "$stages" ] || usage
  home=$(cd "$HOME" 2>/dev/null && pwd -P) || home=$HOME
  "$JQ" -nc --slurpfile b "$before" --slurpfile a "$after" --slurpfile t "$target" --slurpfile s "$stages" \
    --arg home "$home" -f "$SCRIPT_DIR/jq/evaluate.jq" || {
    echo "metrics.sh: evaluate: unreadable or malformed input" >&2
    exit 2
  }
}

# iso <date args>: local ISO 8601 time with a colon in the offset.
iso() {
  date "$@" +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/'
}

# write <file> <content>: through a temp file, so a failed write never leaves a
# partial report that the next run would read as its previous one. The temp
# name is new (mktemp), so a planted symlink is never followed.
write() {
  local tmp=""
  { tmp=$(mktemp "$1.XXXXXX") && printf '%s\n' "$2" >"$tmp" && mv "$tmp" "$1"; } 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null
    echo "metrics.sh: cannot write $1" >&2
    exit 1
  }
}

# Writes the Run (contracts/report.schema.json) as <stamp>.json and its Markdown
# as <stamp>.md into --out, compared with --previous or the newest earlier
# report there, and prints the JSON path.
report() {
  local before="" after="" target="" stages="" previous="" out="" checks="[]" prev=null reason="" err f now stamp run md
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --before) before=$2 ;;
      --after) after=$2 ;;
      --target) target=$2 ;;
      --stages) stages=$2 ;;
      --previous) previous=$2 ;;
      --out) out=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  [ -n "$before" ] && [ -n "$after" ] && [ -n "$target" ] && [ -n "$stages" ] && [ -n "$out" ] || usage
  if ! err=$("$JQ" -e 'type == "array"' "$stages" 2>&1 >/dev/null); then
    echo "metrics.sh: report: $stages is not a JSON array${err:+: $err}" >&2
    exit 2
  fi
  if [ "$after" = - ]; then
    after=/dev/null
  else
    checks=$(evaluate --before "$before" --after "$after" --target "$target" --stages "$stages")
  fi
  if [ -z "$previous" ]; then
    for f in "$out"/*.json; do [ -f "$f" ] && previous=$f; done
  fi
  if [ -z "$previous" ]; then
    reason="no previous report in $out"
  elif ! prev=$("$JQ" -ce 'if type == "object" and .schema == 1 then . else error("not a report") end' "$previous" 2>/dev/null); then
    prev=null
    reason="$previous is missing or not a readable diskdiet report"
  fi
  now=$(date +%s)
  stamp=$(date -r "$now" +%Y-%m-%d-%H%M%S)
  run=$("$JQ" -n --slurpfile b "$before" --slurpfile a "$after" --slurpfile t "$target" --slurpfile s "$stages" \
    --argjson checks "$checks" --argjson prev "$prev" --arg file "$previous" --arg reason "$reason" \
    --arg started "$(iso -r "$before")" --arg finished "$(iso -r "$now")" -f "$SCRIPT_DIR/jq/run.jq") || {
    echo "metrics.sh: report: unreadable or malformed input" >&2
    exit 2
  }
  md=$("$JQ" -r -f "$SCRIPT_DIR/jq/report-md.jq" <<<"$run") || {
    echo "metrics.sh: report: cannot render the Markdown report" >&2
    exit 2
  }
  mkdir -p "$out" 2>/dev/null || {
    echo "metrics.sh: report: cannot write $out" >&2
    exit 1
  }
  write "$out/$stamp.json" "$run"
  write "$out/$stamp.md" "$md"
  echo "$out/$stamp.json"
}

# save <file>: stdin into <file>, only a plain file name directly inside a run
# folder that `mktemp -d "$TMPDIR/diskdiet-XXXXXX"` made. The skill writes
# through this instead of a shell redirect, which Claude Code prompts for.
save() {
  [ $# -eq 1 ] || usage
  local dir name content
  # Read first: stdin can take long, so the checks run right before the write.
  content=$(cat)
  dir=$(dirname "$1")
  name=$(basename "$1")
  case $(basename "$dir")/$name in
    diskdiet-??????/[!.]*) case $name in *[!A-Za-z0-9._-]*) dir="" ;; esac ;;
    *) dir="" ;;
  esac
  if [ -z "$dir" ] || [ ! -d "$dir" ] || [ -L "$dir" ] || [ -L "$1" ] ||
    [ "$(cd "$dir/.." && pwd -P)" != "$(cd "${TMPDIR:-/tmp}" && pwd -P)" ]; then
    echo "metrics.sh: save: not a file in a diskdiet run folder: $1" >&2
    exit 2
  fi
  if [ -z "$content" ]; then
    echo "metrics.sh: save: no input for $1" >&2
    exit 2
  fi
  write "$1" "$content"
}

[ -x "$JQ" ] || {
  echo "metrics.sh: jq is required ($JQ)" >&2
  exit 2
}

case ${1:-} in
  collect) collect ;;
  mole-total) mole_total ;;
  evaluate)
    shift
    evaluate "$@"
    ;;
  report)
    shift
    report "$@"
    ;;
  save)
    shift
    save "$@"
    ;;
  *) usage ;;
esac
