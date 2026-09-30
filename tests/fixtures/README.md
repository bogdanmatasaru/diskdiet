# Fixtures

Captured on macOS 27.0 (Apple Silicon) with Mole 1.56.1, then anonymised: UUIDs set to `00000000-0000-0000-0000-00000000000N`, snapshot hashes zeroed, serial numbers `redacted`, paths under `/private/tmp/diskdiet-home`. Mole ran on a synthetic temp tree, never a real home.

| Fixture | Command | Source |
| --- | --- | --- |
| `df.txt` | `df -k /System/Volumes/Data` | captured |
| `df_root.txt` | `df -k /` (sealed system volume) | captured |
| `df_low.txt` | same, under 20 GB free | synthetic |
| `diskutil_info_root.plist` | `diskutil info -plist /` | captured |
| `diskutil_info_disk0.txt` | `diskutil info disk0` | captured |
| `diskutil_info_disk0_failing.txt` | same, `SMART Status: Failing` | synthetic |
| `diskutil_apfs_snapshots_data.txt` | `diskutil apfs listSnapshots /System/Volumes/Data` | captured (none) |
| `diskutil_apfs_snapshots_data_pinned.txt` | same, one non-purgeable Time Machine snapshot | synthetic, shape from the root capture |
| `diskutil_apfs_snapshots_data_mixed.txt` | same, sealed system snapshot plus two Time Machine snapshots | synthetic, shape from the root capture |
| `diskutil_apfs_snapshots_root.txt` | `diskutil apfs listSnapshots /` | captured |
| `tmutil_snapshots_data.txt` | `tmutil listlocalsnapshots /System/Volumes/Data` | captured (none) |
| `tmutil_snapshots_data_one.txt` | same, one snapshot | synthetic |
| `tmutil_snapshots_data_two.txt` | same, two snapshots | synthetic |
| `tmutil_snapshots_root.txt` | `tmutil listlocalsnapshots /` | captured (none) |
| `memory_pressure.txt` | `memory_pressure -Q` | captured |
| `memory_pressure_low.txt` | same, 8% free | synthetic |
| `sysctl_hw_model.txt` | `sysctl -n hw.model` | captured |
| `sysctl_swapusage.txt` | `sysctl vm.swapusage`, 1 GB used | synthetic |
| `sysctl_swapusage_high.txt` | same, over 8 GB used | captured |
| `pmset_therm.txt` | `pmset -g therm` | captured |
| `pmset_therm_warning.txt` | same, the "No thermal warning" note absent | synthetic; exact warning wording unverified |
| `mdutil.txt` | `mdutil -s /` | captured |
| `mdutil_disabled.txt` | same, indexing disabled | synthetic |
| `system_profiler_power.json` | `system_profiler SPPowerDataType -json` | captured |
| `system_profiler_power_worn.json` | same, health `Service Recommended`, 65% | synthetic |
| `system_profiler_power_desktop.json` | same, no battery | synthetic |
| `sfltool_dumpbtm.txt` | `sfltool dumpbtm`, UIDs -2, 0 and 501 | anonymised: names, ids and UUIDs replaced; record and disposition shapes from a capture (it raised a Touch ID prompt without sudo) |
| `sw_vers.txt` | `sw_vers` | captured |
| `mo_version.txt` | `mo --version` | captured |
| `mo_version_old.txt` | same, 1.50.0 | synthetic |
| `mo_analyze.json` | `mo analyze --json <temp tree>` | captured |
| `mo_analyze_partial.json` | same, `scan_status: partial`, no `large_files` | synthetic |
| `mo_clean_dry_run.txt` | `mo clean --dry-run`, summary block | captured |
| `mo_purge_dry_run.txt` | `mo purge --dry-run` | captured |
| `mo_clean_dry_run_at_least.txt` | same, partial total `At least X` with colour codes | synthetic, line shape from Mole `bin/clean.sh:1984-1991` |
| `mo_clean_dry_run_changed.txt` | same, summary wording changed | synthetic |
| `mo_uninstall_dry_run.txt` | `mo uninstall --dry-run <app>` preview | synthetic, line shapes from Mole `lib/uninstall/batch.sh:1784-1800`; T025 replaces it with a capture |
| `mole-lib/core/base.sh` | Mole `lib/core/base.sh` `DEFAULT_WHITELIST_PATTERNS` | synthetic, same variable shape, no Mole code |

`sfltool dumpbtm` run without root raised a Touch ID prompt on macOS 27 (captured in G3 with the owner present), so `metrics.sh collect` runs it only as root or through a cached `sudo -n`.
