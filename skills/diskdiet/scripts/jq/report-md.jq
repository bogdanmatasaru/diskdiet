def gb: if . == null then "unknown" else "\(.) GB" end;
def cell: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
# Stage notes are written by hand, so a single value or null counts as a list.
def list: if . == null then [] elif type == "array" then map(tostring) else [tostring] end;
def signed: if . == null then "unknown" elif . > 0 then "+\(.) GB" else "\(.) GB" end;
.metrics_before as $b | .metrics_after as $a | .target as $t | .previous as $p
| (if $a.free_gb == null or $b.free_gb == null then null else $a.free_gb - $b.free_gb | . * 100 | round / 100 end) as $run
| "# diskdiet report \(.finished_at)", "",
  "## Summary", "",
  (if $t.gap_gb > 0 then "\($t.free_gb) GB free, \($t.gap_gb) GB short of the \($t.target_gb) GB target."
   else "\($t.free_gb) GB free. Target met (\($t.target_gb) GB)." end),
  (if $p == null then "No baseline: \(.previous_reason)." else "Compared with \($p.file)." end), "",
  "## Space", "",
  "| | Previous run | Before | After | This run | Since previous run |",
  "|---|---|---|---|---|---|",
  "| Free space | \($p.free_gb | gb) | \($b.free_gb | gb) | \($a.free_gb | gb) | \($run | signed) | \($p.delta_free_gb | signed) |",
  "", "Snapshot size is unknown (macOS does not report it), so the target counts it as 0.", "",
  "## Stages", "",
  "| Stage | Answer | Preview | Freed | Notes |", "|---|---|---|---|---|",
  (.stages[] | "| \(.name) | \(if .name == "snapshots" and .answer == "not_applicable" then "skipped (no snapshots)" else .answer end) | \(
    if .preview_gb != null then "\(.preview_gb) GB" elif .preview_items != null then "\(.preview_items) item\(if .preview_items == 1 then "" else "s" end)" else "-" end) | \(
    .freed_gb | if . == null then "-" else "\(.) GB" end) | \(
    [(.recreated | list | if . != [] then "recreated: \(join(", "))" else empty end),
     (.errors | list | if . != [] then "errors: \(join("; "))" else empty end),
     (if .name == "uninstall" and .answer == "yes" then "removed items are in the Trash until you empty it" else empty end)]
    | join("; ") | cell) |"), "",
  "## Checks", "",
  (if $a == null then "Sanity checks not run (the run stopped early)."
   else "| Check | Status | Previous run | Reason |", "|---|---|---|---|",
     (.checks[] | "| \(.name) | \(.status) | \($p.checks.status[.name] // "-") | \(.reason // "" | cell) |") end), "",
  "## What still blocks the target", "",
  (if $t.gap_gb <= 0 then "Nothing. Target met."
   else "- \($t.gap_gb) GB short of the \($t.target_gb) GB target.",
     (.stages[] | select(.answer == "no" or .answer == "skipped")
       | "- \(.name): \(if .answer == "no" then "answered no" else "skipped" end)\(if .preview_gb != null then " (\(.preview_gb) GB previewed)" else "" end)"),
     (($a // $b).snapshots.items[]? | select(.purgeable != true) | "- snapshot \(.name) is not purgeable and pins space"),
     (.stages[] | (.recreated | list) | select(. != []) | "- snapshots recreated after deletion: \(join(", "))"),
     "- Snapshot size is unknown, so snapshots may hold more than the target allows for." end)
