$rows | split("\n") | map(select(. != "") | split("\t")
| {path: .[0], exists: (.[1] == "true"), items: (.[2] | fromjson)})
