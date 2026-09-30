def r2: . * 100 | round / 100;
$b[0] as $b | $a[0] as $a | $t[0] as $t
| if ($b | type) != "object" or ($t.target_gb | type) != "number" then error("inputs are not Metrics and Target") else . end
| ($a // $b).free_gb as $free
| {schema: 1, started_at: $started, finished_at: $finished, machine: $b.machine,
   metrics_before: $b, metrics_after: $a,
   target: ($t + if $free == null then {} else {free_gb: $free, gap_gb: ([0, $t.target_gb - $free] | max | r2)} end),
   stages: $s[0], checks: $checks,
   previous: (if $prev == null then null
     else ($prev.checks // [] | map({key: .name, value: .status}) | from_entries) as $was
       | ($prev.metrics_after // $prev.metrics_before).free_gb as $pf
       | {file: $file, free_gb: $pf,
          delta_free_gb: (if $pf == null or $free == null then null else $free - $pf | r2 end),
          checks: {status: $was, changed: [$checks[] | select($was[.name] != null and $was[.name] != .status) | .name]}}
     end)}
+ if $prev == null then {previous_reason: $reason} else {} end
