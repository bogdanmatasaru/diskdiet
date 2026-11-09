($free | tonumber) as $f
| ($pct | tonumber) as $p
| (($total | tonumber) * (100 - $p) / 100 | ceil) as $t
| {target_gb: $t,
   gap_gb: ([0, $t - $f] | max | . * 100 | round / 100),
   free_gb: $f,
   max_used_pct: $p,
   formula: "free >= total x (100 - \($p))% (at most \($p)% used)"}
