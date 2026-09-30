($free | tonumber) as $f
| (40 + 10 + ($swap | tonumber) + ($caches | tonumber) | ceil) as $t
| {target_gb: $t,
   gap_gb: ([0, $t - $f] | max | . * 100 | round / 100),
   free_gb: $f,
   formula: "40+10+swap+caches (snapshots unknown, counted as 0)",
   caches_unknown: $unknown}
