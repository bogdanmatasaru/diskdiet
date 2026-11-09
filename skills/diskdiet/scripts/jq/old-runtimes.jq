# leftovers.sh, under --max: the ready, deletable simulator runtimes that are
# not the newest ready one of their platform, back no booted device ($booted:
# runtime identifiers) and were not used in the last $mins minutes. Deleting a
# runtime shuts down the simulators booted on it. The id must look like one:
# simctl runtime delete also takes `all`. Input is `simctl runtime list -j`.
objects
| [.[] | select(.state == "Ready" and .deletable == true
    and ([.identifier, .runtimeIdentifier, .platformIdentifier, .version] | map(type) | unique) == ["string"])]
| group_by(.platformIdentifier)[] | sort_by(.version | split(".") | map(tonumber? // 0)) | .[:-1][]
| select(.identifier | test("^[0-9A-Fa-f-]{36}$"))
| select(.runtimeIdentifier | IN($booted[]) | not)
| select((.lastUsedAt | type) != "string" or (.lastUsedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) < now - $mins * 60)
| "\(.identifier) \(.platformIdentifier) (\(.version))"
