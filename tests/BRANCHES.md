# Branch table

kcov has no branch coverage for bash, so every `if`, `case`, `&&` and `||` arm in the helper scripts is listed here with the bats test that takes it. Rows name functions, not line numbers, so they survive edits.

## guard.sh

| Function | Branch | Arm | Test |
| --- | --- | --- | --- |
| main | `if -z HOME` | unset or empty | check: unset or empty HOME exits 2 |
| main | `if -z HOME` | set | check: exact protected path refused |
| `valid_id` | `case` | empty | check: invalid --allow-app is a usage error |
| `valid_id` | `case` | leading dot | check: invalid --allow-app is a usage error |
| `valid_id` | `case` | trailing dot | check: invalid --allow-app is a usage error |
| `valid_id` | `case` | `..` | check: invalid --allow-app is a usage error |
| `valid_id` | `case` | other character | check: invalid --allow-app is a usage error |
| `valid_id` | `case` | has a dot: valid | check: --allow-app allows only that app and its extensions |
| `valid_id` | `case` | no dot | check: invalid --allow-app is a usage error |
| `resolve` | `if -L` | symlink | check: symlink into protected refused |
| `resolve` | `-le 40 \|\|` | loop: fail | check: symlink loop refused |
| `resolve` | target not absolute | relative target | check: relative symlink chain into protected refused |
| `resolve` | target not absolute | absolute target | check: symlink into protected refused |
| `resolve` | `elif -e` | exists | check: exact protected path refused |
| `resolve` | `else` | missing | check: path inside protected refused |
| `resolve` | parent `\|\| return 1` | parent is a loop | check: symlink loop refused |
| `resolve` | `dirname &&` | dirname fails (path too long) | uninstall-check: a path too long to resolve never passes |
| `resolve` | `case basename` | `..` | check: .. inside a missing part is normalised |
| `resolve` | `case basename` | `.` | check: .. inside a missing part is normalised |
| `resolve` | `case basename` | name | check: dangling symlink whose parent is protected refused |
| `pictures_unreadable` | `-d &&` | no Pictures | list: no Pictures folder |
| `pictures_unreadable` | `&& ! ls` | readable | list: built-ins only when no whitelist |
| `pictures_unreadable` | `&& ! ls` | unreadable | list: unreadable Pictures listed whole |
| `builtins` | `if -e` | library found | list: built-ins only when no whitelist |
| `builtins` | `if -e` | no library | list: no Pictures folder |
| `whitelist_entry` | `case` tilde | `~` | check: whitelist lines with ~ and HOME forms protect |
| `whitelist_entry` | `case` tilde | no tilde | check: whitelist lines with ~ and HOME forms protect |
| `whitelist_entry` | `case` | `..` | check: whitelist comments, blanks, .., sentinel and relative lines ignored |
| `whitelist_entry` | `case` | absolute | check: whitelist lines with ~ and HOME forms protect |
| `whitelist_entry` | `case` | comment, blank, sentinel, relative | check: whitelist comments, blanks, .., sentinel and relative lines ignored |
| `add_rule` | `if` glob | glob | check: whitelist glob matches as prefix of its fixed part |
| `add_rule` | `if` glob | concrete | check: exact protected path refused |
| `add_rule` | glob `\|\| r=` | unresolvable | check: rules that cannot be resolved stay literal |
| `add_rule` | concrete `\|\| r=` | unresolvable | check: rules that cannot be resolved stay literal |
| `load_rules` | `if pictures_unreadable` | unreadable | check: unreadable Pictures protects all of Pictures |
| `load_rules` | `if pictures_unreadable` | readable | check: photos library and its content refused |
| `load_rules` | `if -f` whitelist | absent: Mole defaults | check: no whitelist file protects Mole's default list |
| `load_rules` | `if -f` whitelist | exists | check: whitelist lines with ~ and HOME forms protect |
| `load_rules` | `default_whitelist \|\| exit` | not found | check: no whitelist file and no Mole lib exits 2 |
| `load_rules` | `if whitelist_entry` | skipped line | check: whitelist comments, blanks, .., sentinel and relative lines ignored |
| `load_rules` | `case` | glob | check: whitelist glob matches as prefix of its fixed part |
| `load_rules` | `case` | concrete | check: whitelist lines with ~ and HOME forms protect |
| `refusal` | `case` | empty | check: relative and empty paths refused |
| `refusal` | `case` | `~` | check: ~ in an argument expands to HOME |
| `refusal` | `case` | other | check: exact protected path refused |
| `refusal` | `if` not absolute | relative | check: relative and empty paths refused |
| `refusal` | `resolve \|\|` | loop | check: symlink loop refused |
| `refusal` | `if` root | `/` | check: root and home refused |
| `refusal` | `case` /.nofollow | alias | check: /.nofollow alias of a protected path refused |
| `refusal` | `case` /.nofollow | other | check: exact protected path refused |
| `refusal` | `if -n id` | app given | check: --allow-app allows only that app and its extensions |
| `refusal` | `if -n id` | no app | check: exact protected path refused |
| `refusal` | `case` app | the app's container | check: --allow-app allows only that app and its extensions |
| `refusal` | `case` app | inside the app's container | check: --allow-app allows only that app and its extensions |
| `refusal` | `case` app | extension container | check: --allow-app allows only that app and its extensions |
| `refusal` | `case` app | other container | check: --allow-app allows only that app and its extensions |
| `refusal` | `case` inside | equal | check: exact protected path refused |
| `refusal` | `case` inside | below | check: path inside protected refused |
| `refusal` | `case` inside | neither | check: unrelated paths allowed |
| `refusal` | `if` glob | glob prefix hit | check: whitelist glob matches as prefix of its fixed part |
| `refusal` | `if` glob | glob, no hit | check: whitelist glob matches as prefix of its fixed part |
| `refusal` | `case` parent | parent | check: parent of a protected path refused |
| `refusal` | `if inside && in_app` | exempt: rule covers Containers | check: --allow-app allows only that app and its extensions |
| `refusal` | `if inside && in_app` | not exempt: rule inside the app | check: --allow-app keeps other protections |
| `refusal` | `if inside && in_app` | not in the app | check: --allow-app allows only that app and its extensions |
| `refusal` | `if -n hit` | refused | check: exact protected path refused |
| `refusal` | `if -n hit` | next rule | check: unrelated paths allowed |
| `check` | `if --allow-app` | given | check: --allow-app allows only that app and its extensions |
| `check` | `if --allow-app` | not given | check: exact protected path refused |
| `check` | `if $# -lt 2 \|\| ! valid_id` | no id | check: invalid --allow-app is a usage error |
| `check` | `if $# -lt 2 \|\| ! valid_id` | invalid id | check: invalid --allow-app is a usage error |
| `check` | `$# -gt 0 \|\| usage` | no path | usage errors exit 2 |
| `check` | `if -n why` | refused | check: every refused path is reported |
| `check` | `if -n why` | allowed | check: every refused path is reported |
| `check` | `bad = 0 \|\| exit 3` | all allowed | check: unrelated paths allowed |
| `check` | `bad = 0 \|\| exit 3` | any refused | check: every refused path is reported |
| `config_files` | `if` not a regular file | whitelist or whitelist_optimize is a folder | whitelist and check: a whitelist that is not a regular file exits 2 |
| `config_files` | `if` not a regular file | regular or absent | whitelist: idempotent |
| `config_files` | `while ! -e` | missing config folder walked up | check: unsearchable config folder exits 2, never falls back to defaults |
| `config_files` | `if ! -x` | unsearchable | check: unsearchable config folder exits 2, never falls back to defaults |
| `config_files` | `if ! -x` | searchable | whitelist: idempotent |
| script | `ERR` trap | unexpected failure exits 2 | whitelist: unwritable config folder exits 2, never 1 |
| `uninstall_check` | `case` flag | `--shown` | uninstall-check: --shown passes when the new preview lists only shown paths |
| `uninstall_check` | `case` flag | `--preview`: file instead of stdin | uninstall-check: --preview reads the preview from a file |
| `uninstall_check` | `case` flag | other flag | uninstall-check: --allow-app required |
| `uninstall_check` | `if -n shown` | shown path lacking | uninstall-check: --shown refuses a path the shown preview lacked |
| `uninstall_check` | `if -n shown` | all shown | uninstall-check: --shown passes when the new preview lists only shown paths |
| `uninstall_check` | `if -z seen` | shown file unreadable or without paths | uninstall-check: --shown file unreadable or without paths exits 2 |
| `uninstall_check` | usage `\|\|` | wrong count | uninstall-check: --allow-app required |
| `uninstall_check` | usage `\|\|` | wrong flag | uninstall-check: --allow-app required |
| `uninstall_check` | usage `\|\|` | invalid id | uninstall-check: --allow-app required |
| `uninstall_check` | `case` preview | `[Brew]` tag | uninstall-check: Homebrew cask refused, its zap paths are not in the preview |
| `uninstall_check` | `case` preview | no tag | uninstall-check: preview of only the picked app's paths passes |
| `uninstall_check` | `case` line | `~` path | uninstall-check: preview of only the picked app's paths passes |
| `uninstall_check` | `case` line | absolute path | uninstall-check: preview of only the picked app's paths passes |
| `uninstall_check` | `case` line | not a path | uninstall-check: preview of only the picked app's paths passes |
| `uninstall_check` | `if` no path | none | uninstall-check: unparsable input exits 2 |
| `uninstall_check` | `if` no path | some | uninstall-check: protected paths in the preview refused |
| `mole_lib` | `if command -v mo` | found | whitelist: Mole lib next to the resolved Homebrew symlink |
| `mole_lib` | `if command -v mo` | not found | whitelist: no mo on PATH still finds ~/.config/mole/lib |
| `mole_lib` | `if -n d && -f` | `$DISKDIET_MOLE_LIB` | whitelist: new file seeded with Mole defaults, then built-ins |
| `mole_lib` | `if -n d && -f` | pinned `SCRIPT_DIR` | whitelist: Mole lib from the SCRIPT_DIR pinned in the launcher |
| `mole_lib` | `if -n d && -f` | next to launcher | whitelist: Mole lib next to the resolved Homebrew symlink |
| `mole_lib` | `if -n d && -f` | `~/.config/mole/lib` | whitelist: Mole lib from ~/.config/mole/lib |
| `mole_lib` | `if -n d && -f` | none | whitelist: no Mole lib found exits 2 and writes nothing |
| `mole_defaults` | `if on = 0` | before the array | whitelist: new file seeded with Mole defaults, then built-ins |
| `mole_defaults` | `if` declare line | found | whitelist: new file seeded with Mole defaults, then built-ins |
| `mole_defaults` | `if` declare line | never found | whitelist: unparsable Mole defaults exit 2 and write nothing |
| `mole_defaults` | `case )` | entries read | whitelist: new file seeded with Mole defaults, then built-ins |
| `mole_defaults` | `case )` | empty array | whitelist: unparsable Mole defaults exit 2 and write nothing |
| `mole_defaults` | `case` | blank or comment | whitelist: new file seeded with Mole defaults, then built-ins |
| `mole_defaults` | `case` | sentinel | whitelist: new file seeded with Mole defaults, then built-ins |
| `mole_defaults` | `case` | `$HOME` path | whitelist: new file seeded with Mole defaults, then built-ins |
| `mole_defaults` | `case` rest | expansion inside | whitelist: unparsable Mole defaults exit 2 and write nothing |
| `mole_defaults` | `case` | anything else | whitelist: unparsable Mole defaults exit 2 and write nothing |
| `trap` | `-z tmp \|\|` | temp left | whitelist: interrupted write leaves the old file |
| `trap` | `-z tmp \|\|` | nothing left | whitelist: idempotent |
| `write_lines` | `if ! grep` | missing: added | whitelist: existing file kept, only missing lines added in order |
| `write_lines` | `if ! grep` | present: kept | whitelist: existing file kept, only missing lines added in order |
| `write_lines` | `-gt before \|\| return` | nothing added | whitelist: idempotent |
| `excluded_tasks` | `if` path set and protected | protected | whitelist: optimize task excluded when a protected path holds its files |
| `excluded_tasks` | `if` path set and protected | protected path inside the task folder | whitelist: optimize task excluded when a protected path lies inside its folder |
| `excluded_tasks` | `if` path set and protected | no path, or not protected | whitelist: permissions reset excluded in a new whitelist_optimize |
| `whitelist` | `if -n p` excluded task | some | whitelist: optimize task excluded when a protected path holds its files |
| `whitelist` | `if -n p` excluded task | none | whitelist: permissions reset excluded in a new whitelist_optimize |
| `whitelist` | `if pictures_unreadable` | unreadable | whitelist: unreadable Pictures exits 2 with the reason |
| `whitelist` | `if -f` whitelist | exists | whitelist: existing file kept, only missing lines added in order |
| `whitelist` | `if -f` whitelist | absent | whitelist: new file seeded with Mole defaults, then built-ins |
| `default_whitelist` | `mole_lib \|\|` | not found | whitelist: no Mole lib found exits 2 and writes nothing |
| `default_whitelist` | `mole_defaults \|\|` | unparsable | whitelist: unparsable Mole defaults exit 2 and write nothing |
| `whitelist` | `default_whitelist \|\| exit` | fails | whitelist: no Mole lib found exits 2 and writes nothing |
| `whitelist` | `resolve \|\|` | unresolvable | check: rules that cannot be resolved stay literal |
| `whitelist` | `if r != p` | resolved differs | whitelist: resolved form added when HOME is a symlink |
| `whitelist` | `if r != p` | same | whitelist: new file seeded with Mole defaults, then built-ins |
| `whitelist` | `if -f` optimize | exists | whitelist: existing whitelist_optimize kept, task added once |
| `whitelist` | `elif -f` legacy | legacy | whitelist: whitelist_optimize seeded from legacy whitelist_checks |
| `whitelist` | `else` | neither | whitelist: permissions reset excluded in a new whitelist_optimize |
| `whitelist` | `if` added | none | whitelist: idempotent |
| `whitelist` | `if` added | some | whitelist: new file seeded with Mole defaults, then built-ins |
| `list` | `if` glob | concrete listed | list: whitelist concrete paths resolved, globs, sentinel and comments skipped |
| `list` | `if` glob | glob skipped | list: whitelist concrete paths resolved, globs, sentinel and comments skipped |
| main | `command -v jq \|\|` | missing | missing jq exits 2 |
| main | `if $# -gt 0` | no command | usage errors exit 2 |
| main | `case` | `check` | check: exact protected path refused |
| main | `case` | `uninstall-check` | uninstall-check: preview of only the picked app's paths passes |
| main | `case` | `whitelist` | whitelist: idempotent |
| main | `case` | `list` | list: built-ins only when no whitelist |
| main | `case` | `report` | report: writes stamped JSON and Markdown into a new out folder, prints the JSON path |
| main | `case` | unknown | usage errors exit 2 |

## freespace.sh

| Function | Branch | Arm | Test |
| --- | --- | --- | --- |
| `number` | `case` | not a number | freespace: negative or non-numeric argument exits 2 |
| `number` | `case` | number | freespace: target keeps the disk at most N% used |
| `number` | `-le 9` | 10 or more whole digits | freespace: a size of 10 or more digits exits 2 |
| main | `-ge 2 \|\|` | option without value | freespace: missing argument exits 2 |
| main | `case` | `--total`, `--free`, `--max-used-pct` | freespace: arguments in any order |
| main | `case` | unknown option | freespace: unknown option exits 2 |
| main | `if ! number` | missing argument | freespace: missing argument exits 2 |
| main | `if ! number` | valid | freespace: target keeps the disk at most N% used |
| main | `case` percent | 1-99 | freespace: target keeps the disk at most N% used |
| main | `case` percent | 0, 100 or more, decimal | freespace: percent outside 1-99 exits 2 |
| main | `case` total | zero | freespace: zero total exits 2 |
| main | `awk f <= t \|\|` | free above total | freespace: more free space than the disk holds exits 2 |
| main | `awk f <= t \|\|` | free at most total | freespace: more free space than the disk holds exits 2 |
| `evaluate` | `[ $# -ge 2 ] \|\|` | flag without value | evaluate: missing or unreadable input exits 2 |
| `evaluate` | `case` flag | `--before`, `--after`, `--target`, `--stages` | evaluate: healthy metrics pass every check in order |
| `evaluate` | `case` flag | unknown | evaluate: missing or unreadable input exits 2 |
| `evaluate` | required `\|\| usage` | a flag missing | evaluate: missing or unreadable input exits 2 |
| `evaluate` | `pwd -P \|\|` | HOME resolved | evaluate: healthy metrics pass every check in order |
| `evaluate` | jq input shape | not Metrics/Target/StageResult[] | evaluate: missing or unreadable input exits 2 |
| `evaluate` | jq `\|\|` | unreadable or malformed file | evaluate: missing or unreadable input exits 2 |
| `evaluate` | jq `reason` | unavailable entry found | evaluate: free_space unavailable names the df reason |
| `evaluate` | jq `reason` | no entry: not measured | evaluate: spotlight enabled pass, anything else warn, null unavailable |
| `evaluate` | jq free_space | null | evaluate: free_space unavailable names the df reason |
| `evaluate` | jq free_space | pass / warn / fail | evaluate: free_space boundaries 19.9 / 20 / target |
| `evaluate` | jq snapshots | null | evaluate: snapshots purgeable pass, non-purgeable warn named, null unavailable |
| `evaluate` | jq snapshots | count 0 / all purgeable | evaluate: healthy metrics pass every check in order |
| `evaluate` | jq snapshots | not purgeable or unknown flag | evaluate: snapshots purgeable pass, non-purgeable warn named, null unavailable |
| `evaluate` | jq ssd_smart | null / Not Supported / Verified / other | evaluate: ssd_smart Verified pass, other fail, Not Supported and missing unavailable |
| `evaluate` | jq memory | either field null | evaluate: memory boundaries for free percentage and swap |
| `evaluate` | jq memory | pass / warn free / warn swap / fail | evaluate: memory boundaries for free percentage and swap |
| `evaluate` | jq thermal | null / thermal warning / performance warning / none | evaluate: thermal warning of either kind warns, null unavailable |
| `evaluate` | jq spotlight | null / enabled / other | evaluate: spotlight enabled pass, anything else warn, null unavailable |
| `evaluate` | jq battery | null, no unavailable entry: not_applicable | evaluate: no battery is not_applicable, unreadable battery unavailable |
| `evaluate` | jq battery | null with unavailable entry | evaluate: no battery is not_applicable, unreadable battery unavailable |
| `evaluate` | jq battery | capacity or condition missing | evaluate: battery boundaries and conditions |
| `evaluate` | jq battery | fail / warn capacity / warn condition / pass | evaluate: battery boundaries and conditions |
| `evaluate` | jq protected_intact | protected null | evaluate: protected items null before or after is unavailable, never pass |
| `evaluate` | jq protected_intact | same or higher count | evaluate: protected intact with same or higher counts passes |
| `evaluate` | jq protected_intact | gone | evaluate: protected path gone fails, named |
| `evaluate` | jq protected_intact | built-in fewer items | evaluate: built-in Containers or Photos library dropped fails, named |
| `evaluate` | jq protected_intact | whitelist-only fewer items | evaluate: whitelist-only count dropped warns, named |
| `evaluate` | jq protected_intact | uninstall `yes` apps allowed / `no` not allowed | evaluate: Containers dropped only by uninstalled app containers passes |
| `evaluate` | jq protected_intact | items null before / after | evaluate: protected items null before or after is unavailable, never pass |
| `evaluate` | jq protected_intact | missing from after | evaluate: protected path missing from after is unavailable |
| `evaluate` | jq login_items | null / <= 30 / > 30 | evaluate: login_items 30 pass, 31 warn, null unavailable with reason |
| `write` | `\|\|` | write failed, temp removed | report: write failure exits non-zero with a message |
| `report` | `[ $# -ge 2 ] \|\|` | odd arguments | report: missing argument or unreadable metrics exits 2 |
| `report` | `case` | each option / unknown | report: missing argument or unreadable metrics exits 2 |
| `report` | required `\|\|` | argument missing | report: missing argument or unreadable metrics exits 2 |
| `report` | `if ! err` stages | not an array | report: malformed stages exits 2 with the parse error, writes nothing |
| `report` | `if ! err` stages | array | report: writes stamped JSON and Markdown into a new out folder, prints the JSON path |
| `report` | `if` after | `-` | report: after - gives metrics_after null, no checks, target from before |
| `report` | `if` after | file, evaluate fails | report: missing argument or unreadable metrics exits 2 |
| `report` | `if -z previous` loop | newest `*.json` | report: without --previous the newest JSON in out is the previous run |
| `report` | `if -z previous` | none found | report: no earlier report gives previous null with a reason |
| `report` | `elif ! prev` | missing, corrupt, not a report | report: missing or corrupt previous gives previous null with a reason, still completes |
| `report` | `elif ! prev` | valid | report: --previous gives free space, difference and changed check names |
| `report` | jq `error` | before not Metrics | report: missing argument or unreadable metrics exits 2 |
| `report` | jq target | free known | report: target free space and gap taken from after |
| `report` | jq target | free null | report: unreadable after free space keeps the given target |
| `report` | jq previous | after null, before used | report: previous without after uses its before free space |
| `report` | jq previous | free null, no checks | report: previous without free space or checks gives an unknown difference |
| `report` | jq `changed` | same / differs / absent | report: --previous gives free space, difference and changed check names |
| `report` | md render `\|\|` | render fails | report: Markdown render failure exits 2 and writes nothing |
| `report` | md `$run` | before or after free null | report: Markdown complete when before or after free space is unknown |
| `report` | md `list` | null / array / single value | report: stage notes that are not lists still render |
| `report` | `mkdir -p \|\|` | out is a file | report: write failure exits non-zero with a message |
| `report` | md summary | short of target | report: Markdown names what still blocks the target |
| `report` | md summary | target met | report: Markdown has summary, space, stages, checks and blockers sections |
| `report` | md `signed` | null / positive / negative / zero | report: previous without free space or checks gives an unknown difference |
| `report` | md stage answer | snapshots `not_applicable` | report: zero snapshots shows the snapshot stage as skipped |
| `report` | md preview | GB / items / none | report: recreated snapshots and stage errors reported |
| `report` | md notes | recreated, errors with `\|`, Trash | report: recreated snapshots and stage errors reported |
| `report` | md checks | not run | report: after - gives metrics_after null, no checks, target from before |
| `report` | md checks | previous status / `-` | report: --previous gives free space, difference and changed check names |
| `report` | md blockers | answered no, skipped, not purgeable, recreated | report: Markdown names what still blocks the target |
| `report` | md blockers | `not_applicable` stage left out | report: Markdown names what still blocks the target |
| main | `-x jq \|\|` | missing | freespace: missing jq exits 2 |
| jq | `ceil` | fraction rounded up | freespace: target rounded up, decimals accepted |
| jq | `ceil` | whole | freespace: target keeps the disk at most N% used |
| jq | `max` | gap 0 | freespace: gap never negative |
| jq | `max` | gap positive | freespace: target keeps the disk at most N% used |

## metrics.sh

| Function | Branch | Arm | Test |
| --- | --- | --- | --- |
| `int` | `case` | not an integer | collect: unparsable output counts as unavailable |
| `int` | `case` | integer | collect: every Metrics field from healthy fixtures |
| `number` | `case` | not a number | mole-total: changed format prints unknown |
| `number` | `case` | number | mole-total: every unit converted in base 10 |
| `tool` | `&& return 0` | ok | collect: every Metrics field from healthy fixtures |
| `tool` | `&& return 0` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `space` | `tool \|\|` | failed | collect: failing df leaves space fields and disk total null |
| `space` | `if int` | parsed | collect: space from the Data volume, never / |
| `space` | `if int` | unrecognised | collect: unparsable output counts as unavailable |
| `container_free` | `tool \|\|` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `container_free` | `plutil \|\|` | not a plist | collect: unparsable output counts as unavailable |
| `container_free` | `if int` | parsed | collect: every Metrics field from healthy fixtures |
| `snapshots` | tmutil `\|\|` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `snapshots` | diskutil `\|\|` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `snapshots` | awk prefix | Time Machine only | collect: sealed system snapshot ignored, each snapshot flagged |
| `snapshots` | jq `$p[.]` | flag found | collect: one Time Machine snapshot with its purgeable flag |
| `snapshots` | jq `$p[.]` | flag missing | collect: snapshot missing from diskutil has unknown purgeable flag |
| `snapshots` | jq `capture // null` | well-formed name: date | collect: snapshot date only from a well-formed Time Machine name |
| `snapshots` | jq `capture // null` | other name: null | collect: snapshot date only from a well-formed Time Machine name |
| `snapshots` | none | count 0 | collect: every Metrics field from healthy fixtures |
| `memory` | `tool \|\|` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `memory` | `if int` | parsed | collect: warnings, failing SMART, disabled Spotlight, high swap, low memory |
| `memory` | `if int` | unrecognised | collect: unparsable output counts as unavailable |
| `swap` | `tool \|\|` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `swap` | `case` unit | `M` | collect: every Metrics field from healthy fixtures |
| `swap` | `case` unit | `G` | collect: swap reported in G converted |
| `swap` | `if number` | unrecognised | collect: unparsable output counts as unavailable |
| `smart` | `tool \|\|` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `smart` | `if -z` | found | collect: warnings, failing SMART, disabled Spotlight, high swap, low memory |
| `smart` | `if -z` | no SMART line | collect: unparsable output counts as unavailable |
| `thermal` | `tool \|\|` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `thermal` | `case` | recognised | collect: every Metrics field from healthy fixtures |
| `thermal` | `case` | unrecognised | collect: unparsable output counts as unavailable |
| `thermal` | jq `contains` | no warning | collect: every Metrics field from healthy fixtures |
| `thermal` | jq `contains` | warning | collect: warnings, failing SMART, disabled Spotlight, high swap, low memory |
| `spotlight` | `tool \|\|` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `spotlight` | `if -z` | found | collect: every Metrics field from healthy fixtures |
| `spotlight` | `if -z` | no status line | collect: unparsable output counts as unavailable |
| `battery` | `tool \|\|` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `battery` | jq | battery | collect: worn battery parsed |
| `battery` | jq | no battery | collect: no battery gives battery null and no unavailable entry |
| `battery` | jq `\|\|` | not JSON | collect: unparsable output counts as unavailable |
| `login_items` | `if` uid | root | collect: login items read directly when running as root |
| `login_items` | `elif sudo -n` | cached sudo | collect: login items counted for the current UID, enabled login item, app or agent |
| `login_items` | `else` | admin dialog | collect: login items unavailable when they would need an admin dialog |
| `login_items` | `tool \|\|` | failed | collect: each failing tool gives its field null and an unavailable entry |
| `login_items` | `if int` | counted | collect: login items counted for the current UID, enabled login item, app or agent |
| `login_items` | `if int` | no records for the UID | collect: login items unavailable when the current UID has no records |
| `protected` | guard `\|\|` | failed | collect: guard failure makes protected unavailable |
| `protected` | `if -d` | readable folder | collect: protected lists built-ins with top-level item counts |
| `protected` | `if ls` | unreadable folder | collect: unreadable Pictures gives protected an unavailable entry |
| `protected` | `elif -e` | file | collect: protected file counts as one item |
| `protected` | `else` | missing | collect: whitelist path listed, missing one counted as absent |
| `machine` | model `if` | read | collect: every Metrics field from healthy fixtures |
| `machine` | model `if` | failed | collect: unreadable model or macOS version reported as unknown |
| `machine` | `sw_vers` `if` | failed | collect: unreadable model or macOS version reported as unknown |
| `machine` | ProductVersion `if` | found | collect: every Metrics field from healthy fixtures |
| `machine` | ProductVersion `if` | missing | collect: unreadable model or macOS version reported as unknown |
| `collect` | jq `kb_gb`, `gb` | null | collect: failing df leaves space fields and disk total null |
| `collect` | jq `blank` | empty | collect: each failing tool gives its field null and an unavailable entry |
| `mole_total` | sed | purge line | mole-total: purge Would free approximately |
| `mole_total` | sed | clean line | mole-total: clean Potential space |
| `mole_total` | sed | `At least`, colour codes | mole-total: clean At least form, colour codes stripped |
| `mole_total` | `if ! number` | no summary | mole-total: changed format prints unknown |
| `mole_total` | `if ! number` | empty input | mole-total: empty input prints unknown |
| `mole_total` | `case` unit | `B`, `KB`, `MB`, `GB` | mole-total: every unit converted in base 10 |
| main | `-x jq \|\|` | missing | collect: missing jq exits 2 |
| main | `case` | `collect` | collect: every Metrics field from healthy fixtures |
| main | `case` | `mole-total` | mole-total: purge Would free approximately |
| main | `case` | `evaluate` | evaluate: healthy metrics pass every check in order |
| main | `case` | `save` | save: writes stdin into a file of the run folder |
| `save` | usage | not one path | save: exactly one path |
| `save` | `case` folder/name | run folder, plain name | save: writes stdin into a file of the run folder |
| `save` | `case` folder/name | hidden or odd name, other folder | save: refuses any file outside a run folder under TMPDIR |
| `save` | `if` refused | missing, symlinked, symlink file, not under TMPDIR | save: refuses any file outside a run folder under TMPDIR |
| `save` | `if -z content` | empty input | save: empty input exits 2 and writes nothing |
| `save` | `if` refused | run folder swapped while stdin is read | save: run folder swapped for a symlink while stdin is open writes nothing |
| `write` | `mktemp` | planted temp-name symlink | save: a planted temp-name symlink is never followed |
| `write` | `mktemp` | concurrent writers | save: concurrent saves to one file all succeed |
| main | `case` | unknown | usage error exits 2 |

## leftovers.sh

| Function | Branch | Arm | Test |
| --- | --- | --- | --- |
| main | `if -z HOME` | unset or empty | unset HOME exits 2 |
| main | `case` | `list` with arguments, `remove` without ids, unknown, none | usage errors exit 2 |
| main | `if --max` | `--max` after the command | leftovers max: DerivedData built in the last 30 days is a unit |
| main | `if --max` | another flag, or `remove --max` without ids | leftovers max: a bad flag or remove without ids exits 2 |
| main | `if dir` | pattern character in TMPDIR | a glob character in TMPDIR exits 2 |
| `catalog` | `if -n TEMP && ! -L && -O` | TMPDIR set, ours: temp lines added | Xcode previews, XcodeBuildMCP, temp folders and the npm cache are units |
| `catalog` | `if -n TEMP && ! -L && -O` | no TMPDIR | no TMPDIR leaves restart space unknown |
| `catalog` | `if -n TEMP && ! -L && -O` | TMPDIR a symlink | temp folders in a TMPDIR that is a symlink are not units |
| `load_units` | `if xcode-derived-data && MAX = 0 && recent` | `--max`: recent DerivedData kept as a unit | leftovers max: DerivedData built in the last 30 days is a unit |
| `build_dirs` | `while read -d ''` | no build folder | nothing found lists no items and measures restart space |
| `build_dirs` | `NL \|\|` | path with a newline | a build folder whose path holds a newline is not a unit |
| `build_dirs` | `cd root \|\|` | no Projects folder | nothing found lists no items and measures restart space |
| `build_dirs` | `top == root/?*` | repo above the scan root | a build folder ignored only by a repo above Projects is not a unit |
| `build_dirs` | `rev-parse \|\|` | not in a repo | git-ignored build folders under Projects with no tracked file are units |
| `build_dirs` | `&&` chain | repo config runs programs | a build folder in a repo whose config runs programs is not a unit |
| `build_dirs` | `&&` chain | holds its own .git | a build folder that is its own git checkout is not a unit |
| `build_dirs` | `&&` chain | holds a bare repo (`*.git`) | a build folder holding a bare git repo is not a unit |
| `build_dirs` | `&&` chain | find cannot read a subfolder | a build folder with a subfolder find cannot read is not a unit |
| `build_dirs` | `&&` chain | ls-files fails | a build folder git cannot list the files of is not a unit |
| `build_dirs` | `&&` chain | not ignored | git-ignored build folders under Projects with no tracked file are units |
| `build_dirs` | `&&` chain | holds a tracked file | git-ignored build folders under Projects with no tracked file are units |
| `build_dirs` | `&&` chain | ignored, nothing tracked | git-ignored build folders under Projects with no tracked file are units |
| `load_units` | `if git-worktrees \|\| project-build-dirs` | `project-build-dirs` | git-ignored build folders under Projects with no tracked file are units |
| `restart_kb` | `du -I` | code-sign clone left out | Chrome code-sign clones are left out of restart space |
| `restart_kb` | `du -I` | other folder counted | other folders in X count toward restart space |
| `old_runtimes` | `\|\| return 1` | device list fails: no runtime deleted | leftovers max: a runtime whose devices simctl cannot list is not deleted |
| `old-runtimes.jq` | `select` UUID | an id that is not a UUID: left out | leftovers max: a runtime id that is not a UUID is never deleted |
| `old-runtimes.jq` | `select` booted | a booted device runs on it: left out | leftovers max: a runtime a booted device runs on is neither listed nor deleted |
| `old_runtimes` | `state != Shutdown` | a device booting or shutting down on it: left out | leftovers max: a runtime a device is booting or shutting down on is not deleted |
| `old-runtimes.jq` | `group_by` | older runtimes of a platform | leftovers max: every runtime but the newest of its platform is listed and sized |
| `old-runtimes.jq` | `group_by` | one runtime per platform | leftovers max: one runtime per platform lists none and deletes nothing, no error |
| `old-runtimes.jq` | `select` ready | not ready, not deletable, or a field of the wrong type: left out | leftovers max: only ready, deletable runtimes unused for 2 hours are deleted, the newest ready one kept |
| `old-runtimes.jq` | `select` lastUsedAt | used in the last 2 hours: kept | leftovers max: only ready, deletable runtimes unused for 2 hours are deleted, the newest ready one kept |
| `old-runtimes.jq` | `select` lastUsedAt | older, or never used | leftovers max: only ready, deletable runtimes unused for 2 hours are deleted, the newest ready one kept |
| `list` | `if xcode-select` | succeeds | simulator runtimes preview comes from simctl's dry run, sized from its list |
| `list` | `if MAX = 1 && old_runtimes` | runtime list succeeds | leftovers max: every runtime but the newest of its platform is listed and sized |
| `list` | `if MAX = 1 && old_runtimes` | runtime list fails | leftovers max: a runtime list simctl cannot give leaves runtimes unknown |
| `list` | `elif MAX = 0 && simctl` | dry run succeeds | simulator runtimes preview comes from simctl's dry run, sized from its list |
| `list` | `elif MAX = 0 && simctl` | dry run fails | nothing found lists no items and measures restart space |
| `list` | `if sim != null` | runtimes listed: sized from the runtime list | simulator runtimes preview comes from simctl's dry run, sized from its list |
| `list` | `if sim != null` | unknown: no runtime list | leftovers max: a runtime list simctl cannot give leaves runtimes unknown |
| `remove` | `elif MAX = 1` (runtimes) | list fails | leftovers max: a runtime list simctl cannot give is an error, nothing deleted |
| `remove` | `if delete` (runtimes) | succeeds | leftovers max: old runtimes are deleted one by one, the newest kept |
| `remove` | `if delete` (runtimes) | fails: error names the runtime | leftovers max: each runtime delete is reported, a failure does not hide the ones deleted |
| `remove` | `deleted = 0 \|\|` | none deleted: not removed | leftovers max: a failing runtime delete is reported as an error |
| `remove` | `deleted = 0 \|\|` | one deleted: removed | leftovers max: each runtime delete is reported, a failure does not hide the ones deleted |
| `remove` | `-n udid \|\|` | no old runtime: neither removed nor error | leftovers max: one runtime per platform lists none and deletes nothing, no error |
| `old-devices.jq` | `$max == 1` | every shut-down device, never-used ones too | leftovers max: every shut-down simulator device is listed, booted or just used ones are kept |
| `old-devices.jq` | `if $max == 1` age | used in the last 2 hours: kept | leftovers max: every shut-down simulator device is listed, booted or just used ones are kept |
| `load_units` | `if wanted` | id not asked for | remove deletes old units, skips in-use and protected ones |
| `load_units` | `if ! -e && ! -L` | path without a glob is missing | nothing found lists no items and measures restart space |
| `load_units` | `if claude-tmp` | symlink or another owner | a claude temp folder that is a symlink or not ours is skipped |
| `load_units` | `if ! -e && ! -L` | dangling symlink kept | a dangling symlink is still a unit |
| `load_units` | `if *NL*` | newline in the name | a path with a newline in its name is never a unit |
| `restart_kb` | `du \|\| true` | du fails | a size du cannot measure is null and not counted |
| `restart_kb` | `du -I tmp.* -I pytest-of-*` | listed temp folders left out | temp folders counted as units are left out of restart space |
| `in_use` | `-n find` | changed recently | remove deletes old units, skips in-use and protected ones |
| `in_use` | `-n find` | old | remove deletes old units, skips in-use and protected ones |
| `in_use` | `find \|\| return 0` | find cannot read a folder: in use | a unit holding a folder find cannot read is in use, never partly removed |
| `in_use` | `-e \|\| -L \|\| return 1` | missing path: not in use | simulator devices are removed by simctl delete with their udids |
| `list` | `if tmpdir-temp` | temp folder: batched find | thousands of temp folders are listed in under 60 s |
| `list` | `elif in_use` | other unit in use | units in use are never measured, however many |
| `list` | `elif in_use` | other unit not in use | size comes from du, summed over removable units only, not measured in use |
| `list` | `if temp -gt 0` | no temp folder | size comes from du, summed over removable units only, not measured in use |
| `list` | `if paths` | units found: one du for all not in use | size comes from du, summed over removable units only, not measured in use |
| `list` | `if paths` | no unit | nothing found lists no items and measures restart space |
| `check_units` | `if TEMP allowed` | allowed: plain temp folders skip guard | Xcode previews, XcodeBuildMCP, temp folders and the npm cache are units |
| `check_units` | `if TEMP allowed` | a rule inside TEMP: every temp folder checked | a whitelisted temp folder is protected |
| `check_units` | `if tmpdir-temp && ! -L` | a temp folder that is a symlink is checked | a temp folder that links to a protected folder is protected |
| `check_units` | `if tmpdir-temp && ! -L` | another unit under TEMP is checked | a folder under TMPDIR reached through a symlink still goes through guard |
| `check_units` | `if -gt 0` (check) | nothing left to check | Xcode previews, XcodeBuildMCP, temp folders and the npm cache are units |
| `leftover-units.jq` | `mode` | `idle`: units not in use go to du | units in use are never measured, however many |
| `leftover-units.jq` | `if rc` | 0: not protected | list groups every catalog path by id with its units |
| `leftover-units.jq` | `if rc` | 3: this path's refusal lines | a whitelisted path is marked protected |
| `leftover-units.jq` | `if rc` | other: could not check | a guard that cannot check marks every listed unit with its first line |
| `leftover-units.jq` | `$recent[$path]` | a changed path under the unit: in use, size not counted | size comes from du, summed over removable units only, not measured in use |
| `leftover-units.jq` | `$recent[$path]` | nothing changed | list groups every catalog path by id with its units |
| `leftover-units.jq` | `capture` | du gave no line for the unit: kb null | a size du cannot measure is null and not counted |
| `check_units` | no paths | none loaded | nothing found lists no items and measures restart space |
| `refusal` | `if rc` | 0 | remove deletes old units, skips in-use and protected ones |
| `refusal` | `if rc` | 3, line for this path | a whitelisted path is marked protected |
| `refusal` | `if rc` | 3, line for another path | remove deletes old units, skips in-use and protected ones |
| `refusal` | `if rc` | other | a guard that cannot check skips the unit |
| `restart_kb` | `-n TMPDIR \|\|` | unset | no TMPDIR leaves restart space unknown |
| `restart_kb` | `-n "$t$x" \|\|` | nothing measured | a size du cannot measure is null and not counted |
| `list` | `if xcode-select` | fails | without developer tools xcrun is never called |
| `list` | `runtimes \|\|` | runtime list fails | a runtime list simctl cannot give leaves runtime size unknown |
| `remove` | `if id` | `simulator-runtimes` | simulator runtimes are removed by simctl, not rm |
| `remove` | `if id` | not in the catalog | an unknown id removes nothing and exits 2 |
| `remove` | `if refusal` | refused | remove deletes old units, skips in-use and protected ones |
| `remove` | `if in_use` | in use | remove deletes old units, skips in-use and protected ones |
| `remove` | `if rm` | fails | a failed removal is reported as an error |
| `remove` | `if simctl` | succeeds | simulator runtimes are removed by simctl, not rm |
| `remove` | `if simctl` | fails | a failing simctl is reported as an error |
| `remove` | `if simctl` | no matching images | no old simulator runtime is not an error |
| `worktrees` | `-n repo \|\|` | no repo under the root | nothing found lists no items and measures restart space |
| `worktrees` | `case` | `worktree`, `HEAD`, blank line | a clean, old worktree whose commits are on main or a remote is a unit |
| `worktrees` | `case` | `locked` | a worktree with changes, hidden, ignored or skip-worktree files, submodules, unpushed commits, recent files, a lock, no folder, a filter in its repo config or no main HEAD is not a unit |
| `worktrees` | `if first` (HEAD line) | linked worktree, HEAD ignored | a clean, old worktree whose commits are on main or a remote is a unit |
| `worktrees` | `if first` | main worktree block | a clean, old worktree whose commits are on main or a remote is a unit |
| `worktrees` | `elif` | locked; recent (also a repo git cannot read: no folder to walk); `.gitmodules`; own filter config; skip-worktree or assume-unchanged file; gitlink (mode 160000); `git status` fails (folder gone); changed, hidden untracked or ignored files; commits only here; `rev-list` fails (no main HEAD) | a worktree with changes, hidden, ignored or skip-worktree files, submodules, unpushed commits, recent files, a lock, no folder, a filter in its repo config or no main HEAD is not a unit |
| `worktrees` | `elif` | removable, on main or on a remote | a clean, old worktree whose commits are on main or a remote is a unit |
| `load_units` | `if git-worktrees` | paths from git | a clean, old worktree whose commits are on main or a remote is a unit |
| `load_units` | `if xcode-derived-data && recent` | changed in the last 30 days | DerivedData of a project built in the last 30 days is not a unit |
| `load_units` | `if xcode-derived-data && recent` | older, or another id | list groups every catalog path by id with its units |
| `recent` | `find \|\|` | find fails | a worktree with changes, hidden, ignored or skip-worktree files, submodules, unpushed commits, recent files, a lock, no folder, a filter in its repo config or no main HEAD is not a unit |
| `own_drivers` | grep | local filter set | a filter in a repo's config never runs during the scan |
| `old_devices` | `xcode-select \|\|` | fails | without developer tools xcrun is never called |
| `old_devices` | pipeline | simctl fails | a device list simctl cannot give leaves simulator devices unknown |
| `old_devices` | pipeline | succeeds | simulator devices shut down and unused for 30 days are listed with their size |
| `remove` | `if id` | `simulator-devices` | simulator devices are removed by simctl delete with their udids |
| `remove` | `if git-worktrees` | git removes it | remove takes a worktree out through git, not rm |
| `remove` | `if git-worktrees` | git refuses | a worktree git refuses to remove is reported as an error |
| `remove` | `-e \|\| removed` | git fails but the folder is gone | a worktree gone after a failed git remove counts as removed |
| `remove` | `if why` (devices) | device folder refused | a device whose data folder guard refuses is skipped, not deleted |
| `old-devices.jq` | `select` | udid not a UUID, no udid, size not a number | a device record with a bad udid or size is never listed or deleted |
| `remove` | `if devices` | no developer tools | without developer tools simulator devices are an error, xcrun never called |
| `remove` | `if devices` | device list fails | a failing simctl delete or device list is reported as an error |
| `remove` | `deleted = 0 \|\|` (devices) | no old device | no old simulator device deletes nothing |
| `remove` | `elif in_use` (devices) | device folder changed in the last 2 hours | a device whose folder changed in the last 2 hours is skipped, not deleted |
| `remove` | `elif delete` (devices) | succeeds, one simctl delete per udid | simulator devices are removed by simctl delete with their udids |
| `remove` | `elif delete` (devices) | fails: error names the udid | a failing simctl delete or device list is reported as an error |
| `remove` | `deleted = 0 \|\|` (devices) | one deleted, another failed: removed and error | each device delete is reported, a failure does not hide the ones deleted |
| `git_quiet` | (none) | fsmonitor in the repo config is not run | a repo's own git config never runs a command during the scan |
| `worktrees` | `case` | blank lines only (git cannot read the repo) | a repo git cannot read never brings back the previous repo's worktree |
| `load_units` | `if git-worktrees` | any other id: glob expands | list groups every catalog path by id with its units |
| `own_drivers` | grep | no local driver | a clean, old worktree whose commits are on main or a remote is a unit |
| `own_drivers` | `grep -v system\|global` | driver only in the global config | a driver in the owner's global git config does not hide worktrees |
| `remove` | `-e \|\| removed` | folder still there after git fails | a worktree git refuses to remove is reported as an error |
| `remove` | `if git-worktrees` | any other id: `rm -rf` | remove deletes old units, skips in-use and protected ones |
| `remove` | `while read udid && read p` | pairs read, then end of output | simulator devices are removed by simctl delete with their udids |
| `remove` | `if why` (devices) | not refused | simulator devices are removed by simctl delete with their udids |
| `old-devices.jq` | `select` | `dataPath` not an absolute one-line path | a device record with a bad udid or size is never listed or deleted |
| `own_drivers` | grep | partial clone, remote program or ssh command in the repo config | a repo whose config can make git fetch or run a program is never scanned |
| `load_units` | `if git-worktrees` (`set -f`) | worktree path with a pattern character | a worktree path with a pattern character stays literal |
| main | `if dir` | pattern character, backslash or newline in HOME or the claude temp folder | a glob character, backslash or newline in HOME or the claude temp folder exits 2 |
| `remove` | `if id` | newline in the id | an unknown id removes nothing and exits 2 |
| `worktrees` | `elif` | newline in the worktree path | a newline in a worktree path never makes another path a unit |
| `worktrees` | `elif` | `.git` folder of any case below the top | a worktree holding a .git folder git status cannot see is not a unit |
| `worktrees` | `find "$1/"` | Projects is a symlink | a Projects folder that is a symlink is scanned |
| `load_units` | `sort -u` | same worktree from two `.git` folders | a worktree reached from two .git folders is one unit |
| `old-devices.jq` | `select(length == 1)` | not one JSON document | a device list of two documents leaves devices unknown, a repeated device is deleted once |
| `old-devices.jq` | `unique_by` | repeated udid | a device list of two documents leaves devices unknown, a repeated device is deleted once |
