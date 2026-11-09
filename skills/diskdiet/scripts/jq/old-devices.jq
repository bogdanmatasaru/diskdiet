# leftovers.sh: simulator devices shut down and unused for $days days. A
# device without lastUsedAt was never booted since it was made; it is kept,
# except under --max ($max 1), which takes every shut-down device not used in
# the last $mins minutes.
# The udid must look like one: simctl delete also takes `all`. Input is
# slurped: anything but one JSON document gives no output.
select(length == 1) | [.[0].devices[][]
  | select(.state == "Shutdown" and ($max == 1 or (.lastUsedAt | type) == "string") and (.dataPath | type) == "string" and (.dataPath | test("^/[^\n]*$")))
  | select(.udid | strings | test("^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$"))
  | select((.lastUsedAt | type) != "string" or (.lastUsedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) < now - (if $max == 1 then $mins * 60 else $days * 86400 end))
  | {udid, name, dataPath, bytes: ((.dataPathSize | numbers) // null)}] | unique_by(.udid)
