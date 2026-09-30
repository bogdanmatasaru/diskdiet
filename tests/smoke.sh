#!/bin/bash
# Smoke target for the harness: proves kcov counts lines of a /bin/bash script.
set -euo pipefail

if [ "${1:-}" = "hello" ]; then
  echo "hello"
else
  echo "usage: smoke.sh hello" >&2
  exit 2
fi
