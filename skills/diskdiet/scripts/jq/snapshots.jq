($names | split("\n") | map(select(. != ""))) as $n
| ($flags | split("\n") | map(select(. != "") | split(" ") | {key: .[0], value: (.[1] == "Yes")}) | from_entries) as $p
| {count: ($n | length), items: [$n[] | {name: ., purgeable: $p[.], date: (capture("^com\\.apple\\.TimeMachine\\.(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6})\\.local$").d // null)}]}
