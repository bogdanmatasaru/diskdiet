# leftovers.sh list, from NUL-separated fields. A unit is in use when one of
# find's recently changed paths is it or lies under it.
# --arg mode idle: input is find's paths, then every unit path; prints the
# units not in use, each followed by NUL, for du.
# --arg mode units: input is find's paths, du's sizes, guard's exit code and
# messages, then id and path of each unit; prints one unit object a line. An
# in-use unit's size is not counted; kb is null when du gave none; protected
# holds guard's refusal lines for the path, or null when allowed.
def up: ., (if test("^/.*/") then sub("/[^/]*$"; "") | up else empty end);
def recent: [split("\n")[] | select(. != "") | up | {(.): true}] | add // {};
split("\u0000")
| (.[0] | recent) as $recent
| if $mode == "idle" then
    .[1:-1][] | select($recent[.] | not) | . + "\u0000"
  else
    ([.[1] | split("\n")[] | capture("^(?<kb>[0-9]+)\t(?<p>.*)$") | {(.p): (.kb | tonumber)}] | add // {}) as $kb
    | .[2] as $rc
    | (.[3] | split("\n")) as $guard
    | .[4:-1] | range(0; length; 2) as $k | .[$k:$k + 2] as [$id, $path]
    | ($recent[$path] // false) as $use
    | (if $rc == "0" then []
       elif $rc == "3" then [$guard[] | select(startswith("refused: " + $path + " ("))]
       else ["could not check: " + $guard[0]] end) as $why
    | {id: $id, path: $path, kb: (if $use then null else $kb[$path] end), in_use: $use,
       protected: (if $why == [] then null else $why | join("\n") end)}
  end
