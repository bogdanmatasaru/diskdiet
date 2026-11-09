# leftovers.sh list: groups the units by id. An item's gb counts only the
# units that would be removed (not in use, not protected). Only the 10
# biggest units are listed, so hundreds of temp folders stay readable.
def gb: if . == null then null else . / 1048576 * 100 | round / 100 end;
def bytes_gb: if . == null then null else . / 1024 | gb end;

{
  restart_gb: ($restart | tonumber? // null | gb),
  simulator_runtimes: $sim,
  # simctl's dry run names each runtime by UUID; its list has the size.
  simulator_runtimes_gb: ([$sim[]? | capture("(?<u>[0-9A-Fa-f-]{36})").u | $runtimes[.].sizeBytes // empty] | add // null | bytes_gb),
  simulator_devices: (if $devices == null then null else $devices | map({udid, name, gb: (.bytes | bytes_gb)}) end),
  simulator_devices_gb: ([$devices[]?.bytes // empty] | add // null | bytes_gb),
  items: (group_by(.id) | map({
    id: .[0].id,
    gb: ([.[] | select(.in_use | not) | select(.protected == null) | .kb // 0] | add // 0 | gb),
    count: length,
    in_use: map(select(.in_use)) | length,
    protected: map(select(.protected != null)) | length,
    units: sort_by(-(.kb // 0)) | .[:10] | map(.gb = (.kb | gb) | del(.kb, .id))
  }))
}
