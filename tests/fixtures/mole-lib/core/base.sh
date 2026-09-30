#!/bin/bash
# Synthetic stand-in for Mole's lib/core/base.sh, written for diskdiet's tests.
# Holds only the variable shape guard.sh parses; no Mole code.
# shellcheck disable=SC2034 # read as text by guard.sh, never sourced
readonly FINDER_METADATA_SENTINEL="FINDER_METADATA"

declare -a DEFAULT_WHITELIST_PATTERNS=(
    "$HOME/Library/Caches/example-tool*"
    "$HOME/.example/models/*"
    "$HOME/Library/Application Support/JetBrains*"

    # iCloud Drive
    "$HOME/Library/Mobile Documents*"
    "$FINDER_METADATA_SENTINEL"
)
