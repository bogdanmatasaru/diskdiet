---
schema_version: "1.1"
runs: 2
timeout_seconds: 600
name: std-precheck
description: "The run resolves mo and brew to the eval stubs and has a temp HOME."
max_turns: 4
---
Run exactly this one command and show its full output, nothing else: `command -v mo tmutil brew df rm; echo "HOME=$HOME"`
