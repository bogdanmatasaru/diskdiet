#!/bin/bash
# Prints the free space that keeps this Mac at most N% used and how far it is from it.
set -euo pipefail

JQ=${DISKDIET_JQ:-/usr/bin/jq}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  echo "usage: freespace.sh --total GB --free GB --max-used-pct 1-99" >&2
  exit 2
}

number() {
  case $1 in
    "" | *[!0-9.]* | .* | *. | *.*.*) return 1 ;;
  esac
  # A billion GB or more is a typo; jq would clamp it to its largest number.
  local whole=${1%%.*}
  [ "${#whole}" -le 9 ]
}

total="" free="" pct=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case $1 in
    --total) total=$2 ;;
    --free) free=$2 ;;
    --max-used-pct) pct=$2 ;;
    *) usage ;;
  esac
  shift 2
done

if ! number "$total" || ! number "$free"; then usage; fi
case $pct in
  [1-9] | [1-9][0-9]) ;;
  *) usage ;;
esac
case $total in *[1-9]*) ;; *) usage ;; esac
awk -v f="$free" -v t="$total" 'BEGIN { exit !(f <= t) }' || usage

[ -x "$JQ" ] || {
  echo "freespace.sh: jq is required ($JQ)" >&2
  exit 2
}

"$JQ" -nc --arg total "$total" --arg free "$free" --arg pct "$pct" -f "$SCRIPT_DIR/jq/freespace.jq"
