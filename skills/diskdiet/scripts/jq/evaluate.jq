$b[0] as $b | $a[0] as $a | $t[0] as $t | $s[0] as $s
| if ([$b, $a] | map(type) | unique) != ["object"] or ($t.target_gb | type) != "number"
    or ($t.gap_gb | type) != "number" or ($s | type) != "array"
  then error("inputs are not Metrics, Metrics, Target and StageResult[]") else . end
| def check($n; $st; $v; $th; $r): {name: $n, status: $st, value: $v, threshold: $th, reason: $r};
  def reason($m; $f): [$m.unavailable[]? | select(.field as $x | $f | index($x)) | .reason]
    | if length > 0 then join("; ") else "not measured" end;
  def na($n; $f): check($n; "unavailable"; null; null; reason($a; $f));
  def builtin: . == ($home + "/Library/Containers") or . == ($home + "/Pictures")
    or (startswith($home + "/Pictures/") and endswith(".photoslibrary"));
[
  (if $a.free_gb == null then na("free_space"; ["free_gb"])
   else $a.free_gb as $f
     | check("free_space"; if $f >= $t.target_gb then "pass" elif $f >= 20 then "warn" else "fail" end;
         $f; {target_gb: $t.target_gb, fail_below_gb: 20};
         if $f >= $t.target_gb then null else "\($f) GB free, target \($t.target_gb) GB" end)
   end),
  (if $a.snapshots == null then na("snapshots"; ["snapshots"])
   else [$a.snapshots.items[] | select(.purgeable != true) | .name] as $p
     | if $p == [] then check("snapshots"; "pass"; $a.snapshots.count; "all purgeable"; null)
       else check("snapshots"; "warn"; $p; "all purgeable"; "not purgeable, pins the container: \($p | join(", "))") end
   end),
  (if $a.smart == null then na("ssd_smart"; ["smart"])
   elif $a.smart == "Not Supported" then check("ssd_smart"; "unavailable"; $a.smart; "Verified"; "SMART not supported")
   elif $a.smart == "Verified" then check("ssd_smart"; "pass"; $a.smart; "Verified"; null)
   else check("ssd_smart"; "fail"; $a.smart; "Verified"; "SMART status \($a.smart)") end),
  (if $a.memory_free_pct == null or $a.swap_used_gb == null then na("memory"; ["memory_free_pct", "swap_used_gb"])
   else {free_pct: $a.memory_free_pct, swap_used_gb: $a.swap_used_gb} as $v
     | check("memory";
         if $v.free_pct < 10 then "fail" elif $v.free_pct < 20 or $v.swap_used_gb > 8 then "warn" else "pass" end;
         $v; {free_pct_min: 20, fail_below_pct: 10, swap_max_gb: 8};
         if $v.free_pct >= 20 and $v.swap_used_gb <= 8 then null
         else "\($v.free_pct)% memory free, \($v.swap_used_gb) GB swap used" end)
   end),
  (if $a.thermal == null then na("thermal"; ["thermal"])
   elif $a.thermal.thermal_warning or $a.thermal.performance_warning
   then check("thermal"; "warn"; $a.thermal; "no warning recorded"; "a thermal or performance warning was recorded")
   else check("thermal"; "pass"; $a.thermal; "no warning recorded"; null) end),
  (if $a.spotlight == null then na("spotlight"; ["spotlight"])
   elif $a.spotlight | startswith("Indexing enabled") then check("spotlight"; "pass"; $a.spotlight; "Indexing enabled"; null)
   else check("spotlight"; "warn"; $a.spotlight; "Indexing enabled"; "Spotlight: \($a.spotlight)") end),
  (if $a.battery == null then
     if [$a.unavailable[]? | select(.field == "battery")] == [] then check("battery"; "not_applicable"; null; null; "no battery")
     else na("battery"; ["battery"]) end
   elif $a.battery.max_capacity_pct == null or $a.battery.condition == null
   then check("battery"; "unavailable"; $a.battery; null; "battery health not reported")
   else $a.battery as $v | {max_capacity_min_pct: 80, fail_below_pct: 70, condition: ["Good", "Normal"]} as $th
     | if $v.max_capacity_pct < 70 then check("battery"; "fail"; $v; $th; "maximum capacity \($v.max_capacity_pct)%")
       elif $v.max_capacity_pct < 80 or ($v.condition | IN("Good", "Normal") | not)
       then check("battery"; "warn"; $v; $th; "maximum capacity \($v.max_capacity_pct)%, condition \($v.condition)")
       else check("battery"; "pass"; $v; $th; null) end
   end),
  (if $b.protected == null or $a.protected == null
   then check("protected_intact"; "unavailable"; null; null; reason({unavailable: ($b.unavailable + $a.unavailable)}; ["protected"]))
   else ([$s[] | select(.name == "uninstall" and .answer == "yes") | .apps // [] | .[]] | unique | length) as $removed
     | ($a.protected | map({key: .path, value: .}) | from_entries) as $after
     | [$b.protected[] | select(.exists) | . as $x | $after[$x.path] as $y
         | (if $x.path == $home + "/Library/Containers" then $removed else 0 end) as $allowed
         | {path: $x.path, before: $x.items, after: $y.items,
            problem: (if $y == null then "not measured after"
              elif $y.exists | not then "gone"
              elif $x.items == null or $y.items == null then "not readable (items null)"
              elif $y.items + $allowed >= $x.items then null
              elif $x.path | builtin then "fewer items"
              else "fewer items (whitelist)" end)}
         | select(.problem != null)] as $p
     | [$p[] | .problem] as $k
     | check("protected_intact";
         if any($k[]; . == "gone" or . == "fewer items") then "fail"
         elif any($k[]; startswith("not ")) then "unavailable"
         elif $k != [] then "warn" else "pass" end;
         $p; "every protected path still there with no fewer items";
         if $p == [] then null else [$p[] | "\(.path): \(.problem)"] | join("; ") end)
   end),
  (if $a.login_items == null then na("login_items"; ["login_items"])
   elif $a.login_items <= 30 then check("login_items"; "pass"; $a.login_items; 30; null)
   else check("login_items"; "warn"; $a.login_items; 30; "\($a.login_items) enabled login items") end)
]
