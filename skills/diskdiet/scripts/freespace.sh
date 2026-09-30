#!/bin/bash
# Prints the free space this Mac should keep and how far it is from it.
set -euo pipefail

JQ=${DISKDIET_JQ:-/usr/bin/jq}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  echo "usage: freespace.sh --free GB --swap GB --caches GB|unknown" >&2
  exit 2
}

number() {
  case $1 in
    "" | *[!0-9.]* | .* | *. | *.*.*) return 1 ;;
  esac
}

free="" swap="" caches=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case $1 in
    --free) free=$2 ;;
    --swap) swap=$2 ;;
    --caches) caches=$2 ;;
    *) usage ;;
  esac
  shift 2
done

caches_unknown=false
if [ "$caches" = unknown ]; then
  caches=0
  caches_unknown=true
fi
if ! number "$free" || ! number "$swap" || ! number "$caches"; then usage; fi

[ -x "$JQ" ] || {
  echo "freespace.sh: jq is required ($JQ)" >&2
  exit 2
}

"$JQ" -nc --arg free "$free" --arg swap "$swap" --arg caches "$caches" --argjson unknown "$caches_unknown" -f "$SCRIPT_DIR/jq/freespace.jq"
