def gb: . / 1e9 * 100 | round / 100;
def kb_gb: if . == null then null else . * 1024 | gb end;
def blank: if . == "" then null else . end;
{free_gb: ($space[2] | kb_gb), used_gb: ($space[1] | kb_gb), total_gb: ($space[0] | kb_gb), used_pct: $space[3],
 container_free_gb: (if $container == null then null else $container | gb end),
 snapshots: $snapshots,
 swap_used_gb: (if $swap == null then null else $swap[0] * $swap[1] | gb end),
 memory_free_pct: $memory,
 smart: ($smart | blank), thermal: $thermal, spotlight: ($spotlight | blank),
 battery: $battery, login_items: $login, protected: $protected,
 machine: {model: $model, macos: $macos, disk_total_gb: ($space[0] | kb_gb)},
 unavailable: ($unavailable | split("\n") | map(select(. != "") | split("\t") | {field: .[0], reason: .[1]}))}
