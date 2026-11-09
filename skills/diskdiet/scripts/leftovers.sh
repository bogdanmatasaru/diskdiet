#!/bin/bash
# Lists and removes developer leftovers that Mole does not clean: a fixed
# catalog of paths, each checked by guard.sh and skipped while in use.
# shellcheck disable=SC2016 # $names in jq programs are jq variables
set -Eeuo pipefail
# Exit codes are 0 or 2 only: any unexpected failure means "could not run".
trap 'exit 2' ERR

JQ=${DISKDIET_JQ:-/usr/bin/jq}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# A path with a file changed this recently belongs to something running.
IN_USE_MINUTES=120
# Simulators, worktrees and DerivedData unused this long are leftovers.
UNUSED_DAYS=30
# --max drops that age rule: every shut-down device, all DerivedData and
# every simulator runtime but the newest of its platform.
MAX=0
NL=$'\n'

usage() {
  echo "usage: leftovers.sh list [--max] | remove [--max] <id>..." >&2
  exit 2
}

if [ -z "${HOME:-}" ]; then
  echo "leftovers.sh: HOME is not set" >&2
  exit 2
fi
CLAUDE_TMP=${DISKDIET_CLAUDE_TMP:-/private/tmp/claude-$(id -u)}
TEMP=${TMPDIR:+${TMPDIR%/}}
# All three expand as globs in the catalog: a pattern character or backslash
# would reach other folders, a newline would add a catalog line.
for dir in "$HOME" "$CLAUDE_TMP" "$TEMP"; do
  if [[ $dir == *[\\*?[]* || $dir == *"$NL"* ]]; then
    echo "leftovers.sh: unsupported characters in $dir" >&2
    exit 2
  fi
done

# id|glob: every match of the glob is one unit, removed whole.
catalog() {
  cat <<EOF
android-avd|$HOME/.android/avd/*
android-system-images|$HOME/Library/Android/sdk/system-images/*
claude-tmp|$CLAUDE_TMP/*
claude-vm-bundles|$HOME/Library/Application Support/Claude/vm_bundles
git-worktrees|$HOME/Projects
gradle-caches|$HOME/.gradle/caches
lm-studio-models|$HOME/.lmstudio/models/*/*
npm-cache|$HOME/.npm/_cacache
playwright|$HOME/Library/Caches/ms-playwright/*
project-build-dirs|$HOME/Projects
uv-cache|$HOME/.cache/uv
xcode-derived-data|$HOME/Library/Developer/Xcode/DerivedData/*
xcode-device-support|$HOME/Library/Developer/Xcode/*DeviceSupport/*
xcode-previews|$HOME/Library/Developer/Xcode/UserData/Previews
xcodebuildmcp|$HOME/Library/Developer/XcodeBuildMCP/*
EOF
  # Without TMPDIR the globs would start at /; TMPDIR comes from the
  # environment, so a symlink or another user's folder is not scanned.
  if [ -n "$TEMP" ] && [ ! -L "$TEMP" ] && [ -O "$TEMP" ]; then
    printf 'tmpdir-temp|%s\n' "$TEMP/tmp.*" "$TEMP/pytest-of-*"
  fi
}

# A repo's own .git/config can name commands git runs during status; a repo
# unpacked from an archive brings its config along.
# fsmonitor, hooks and lazy fetches are switched off; a repo or worktree whose
# own config sets filters, diff drivers, includes, a partial clone, remote
# programs or an ssh command is not scanned at all, nor one with
# submodules or other nested repos (gitlinks), whose configs are their own. No optional locks: the scan never
# writes the index under a git the owner is running.
git_quiet() { GIT_NO_LAZY_FETCH=1 git --no-optional-locks -c core.fsmonitor=false -c core.hooksPath=/dev/null "$@"; }
own_drivers() {
  git_quiet -C "$1" config --show-scope --get-regexp \
    '^(filter|diff|include|includeif)\.|^extensions\.partialclone|^remote\..*\.(uploadpack|receivepack|promisor|vcs)$|^core\.(sshcommand|gitproxy|askpass)$' 2>/dev/null |
    grep -qvE '^(system|global)'
}

# worktrees <root>: linked worktrees of the git repos under root that git can
# remove without losing work: not locked, unchanged for UNUSED_DAYS days, no
# changed, untracked or ignored file (git worktree remove deletes ignored
# ones), no file whose changes git hides (skip-worktree, assume-unchanged), and
# every commit on a remote or in the main worktree's HEAD. A path with a
# newline is skipped, and so is a .git folder inside: status never looks in one.
worktrees() {
  local repo line wt="" main="" first locked out
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    # A repo git cannot read gives no blocks; nothing may carry over.
    first=1 wt="" main="" locked=0
    while IFS= read -r -d '' line; do
      case $line in
        "worktree "*) wt=${line#worktree } locked=0 ;;
        "HEAD "*) if [ "$first" = 1 ]; then main=${line#HEAD }; fi ;;
        locked*) locked=1 ;;
        "")
          if [ "$first" = 1 ]; then
            first=0
          elif [ "$locked" = 0 ] && [[ $wt != *"$NL"* ]] && ! recent "$wt" && [ ! -e "$wt/.gitmodules" ] && ! own_drivers "$wt" &&
            [ -z "$(find "$wt" -mindepth 2 -iname .git -print -quit 2>/dev/null)" ] &&
            out=$(git_quiet -C "$wt" ls-files -s -v 2>/dev/null) && ! grep -qE '^([a-zS]|. 160000 )' <<<"$out" &&
            out=$(git_quiet -C "$wt" status --porcelain --untracked-files=all --ignored 2>/dev/null) && [ -z "$out" ] &&
            out=$(git_quiet -C "$wt" rev-list -n1 HEAD --not --remotes "$main" 2>/dev/null) && [ -z "$out" ]; then
            echo "$wt"
          fi
          ;;
      esac
    done < <(git_quiet -C "${repo%/.git}" worktree list --porcelain -z 2>/dev/null)
  done <<<"$(find "$1/" -maxdepth 4 -name .git -type d -prune 2>/dev/null)"
}

# build_dirs <root>: build output folders in the git repos under root that git
# ignores and that hold no tracked file and no checkout or bare repo of their
# own (a folder find cannot read might hide one). The repo
# must lie under root: a dotfiles repo in HOME that ignores everything says
# nothing about a project with no repo. A repo whose config can run a program
# is skipped, as in worktrees().
build_dirs() {
  local p top out root
  root=$(cd "$1" 2>/dev/null && pwd -P) || return 0
  while IFS= read -r -d '' p; do
    [[ $p != *"$NL"* ]] || continue
    top=$(git_quiet -C "${p%/*}" rev-parse --show-toplevel 2>/dev/null) || continue
    [[ $top == "$root"/?* ]] && ! own_drivers "$top" &&
      git_quiet -C "$top" check-ignore -q -- "$p" 2>/dev/null &&
      out=$(git_quiet -C "$top" ls-files -- "$p" 2>/dev/null) && [ -z "$out" ] &&
      out=$(find "$p" -iname '*.git' -print -quit 2>/dev/null) && [ -z "$out" ] &&
      echo "$p"
  done < <(find "$1/" -maxdepth 6 -name .git -prune -o -type d \( -name node_modules -o -name .build -o -name build -o -name DerivedData -o -name Pods -o -name .venv -o -name target -o -name dist -o -name .next \) -print0 -prune 2>/dev/null)
  # The last folder's failed check is no failure of the scan.
  return 0
}

# recent <path>: something under path changed in the last UNUSED_DAYS days.
# A folder find cannot read counts as recent.
recent() {
  local out
  out=$(find "$1" -mtime "-$UNUSED_DAYS" -print -quit 2>/dev/null) || return 0
  [ -n "$out" ]
}

ids=()
paths=()
# load_units [id...]: fills ids and paths with the catalog's existing matches,
# for the given ids or all of them.
load_units() {
  local id glob p wanted=" $* "
  local IFS=$NL
  shopt -s nullglob
  while IFS='|' read -r id glob; do
    if [ "$wanted" != "  " ] && [[ $wanted != *" $id "* ]]; then continue; fi
    # /private/tmp is shared: another user could plant the folder as a symlink.
    if [ "$id" = claude-tmp ] && { [ -L "$CLAUDE_TMP" ] || [ ! -O "$CLAUDE_TMP" ]; }; then continue; fi
    if [ "$id" = git-worktrees ] || [ "$id" = project-build-dirs ]; then
      # Two .git folders can reach the same repo.
      if [ "$id" = git-worktrees ]; then glob=$(worktrees "$glob"); else glob=$(build_dirs "$glob"); fi
      glob=$(LC_ALL=C sort -u <<<"$glob")
      # Paths from git, not globs: a pattern character in one stays literal.
      set -f
    fi
    # shellcheck disable=SC2206 # the glob expands on purpose; IFS keeps spaces
    for p in $glob; do
      if [ ! -e "$p" ] && [ ! -L "$p" ]; then continue; fi
      if [ "$id" = xcode-derived-data ] && [ "$MAX" = 0 ] && recent "$p"; then continue; fi
      # guard.sh reports one refusal per line, so a newline would hide one.
      if [[ $p == *"$NL"* ]]; then continue; fi
      ids+=("$id")
      paths+=("$p")
    done
    set +f
  done <<<"$(catalog)"
  shopt -u nullglob
}

# A folder find cannot read counts as in use: rm would remove what is around it.
in_use() {
  local out
  [ -e "$1" ] || [ -L "$1" ] || return 1
  out=$(find "$1" -mmin "-$IN_USE_MINUTES" -print -quit 2>/dev/null) || return 0
  [ -n "$out" ]
}

# check_units: one guard.sh check for every loaded path (guard reloads its
# rules on each call); sets guard_rc and guard_err for refusal.
guard_rc=0
guard_err=""
check_units() {
  local i p check=() temp_ok=0
  # guard refuses a path only when a rule lies inside or above it, so when it
  # allows TEMP it allows every temp folder right under TEMP that is not a
  # symlink: the thousands of them skip guard's cost of about 20 ms a path.
  # Deeper units could sit behind a symlinked folder.
  if [ -n "$TEMP" ] && (trap - ERR; "$BASH" "$SCRIPT_DIR/guard.sh" check "$TEMP" >/dev/null 2>&1); then temp_ok=1; fi
  for i in "${!paths[@]}"; do
    p=${paths[i]}
    if [ "$temp_ok" = 1 ] && [ "${ids[i]:-}" = tmpdir-temp ] && [ ! -L "$p" ]; then continue; fi
    check+=("$p")
  done
  [ "${#check[@]}" -gt 0 ] || return 0
  # The subshell drops the ERR trap, or bash 3.2 turns guard's exit 3 into 2.
  guard_err=$(trap - ERR; "$BASH" "$SCRIPT_DIR/guard.sh" check "${check[@]}" 2>&1 >/dev/null) || guard_rc=$?
}

# refusal <path>: why guard.sh refuses the path, or nothing.
refusal() {
  local line
  if [ "$guard_rc" = 3 ]; then
    # grep first: a bash loop over every line for every unit is quadratic.
    # ponytail: still one grep per unit, about 44s at 2,000 refused units;
    # match in one pass if guard.sh ever prints path and reason as fields.
    while IFS= read -r line; do
      if [[ $line == "refused: $1 ("* ]]; then echo "$line"; fi
    done <<<"$(grep -F -- "refused: $1 (" <<<"$guard_err" || true)"
  elif [ "$guard_rc" != 0 ]; then
    # Only the first line: the rest would be copied into every unit.
    echo "could not check: ${guard_err%%"$NL"*}"
  fi
}

# Chrome's code-sign clones in X share their blocks with Chrome.app: deleting
# them frees nothing (109 clones, 0 GB on 2026-11-09), so they are not counted.
restart_kb() {
  local base t x
  [ -n "$TEMP" ] || return 0
  base=$(dirname "$TEMP")
  # The temp folders leftovers lists are counted there, not here.
  t=$(du -sk -I 'tmp.*' -I 'pytest-of-*' "$base/T" 2>/dev/null | cut -f1 || true)
  x=$(du -sk -I '*code_sign_clone' "$base/X" 2>/dev/null | cut -f1 || true)
  # Nothing measured is unknown, not zero.
  [ -n "$t$x" ] || return 0
  echo $((${t:-0} + ${x:-0}))
}

# old_devices: simulator devices shut down and unused for UNUSED_DAYS days, as
# JSON. Without developer tools xcrun opens an install dialog instead of failing.
old_devices() {
  xcode-select -p >/dev/null 2>&1 || return 1
  xcrun simctl list devices -j 2>/dev/null | "$JQ" -sec --argjson days "$UNUSED_DAYS" --argjson max "$MAX" --argjson mins "$IN_USE_MINUTES" -f "$SCRIPT_DIR/jq/old-devices.jq" 2>/dev/null
}

# old_runtimes: under --max, the simulator runtimes jq/old-runtimes.jq takes,
# one "<id> <platform> (<version>)" line each. A device list simctl cannot give
# fails: a booted device would go unseen. A device booting or shutting down
# counts as booted.
old_runtimes() {
  local booted
  booted=$(xcrun simctl list devices -j 2>/dev/null | "$JQ" -ec '[.devices | to_entries[] | select(any(.value[]; .state != "Shutdown")) | .key]' 2>/dev/null) || return 1
  xcrun simctl runtime list -j 2>/dev/null | "$JQ" -r --argjson mins "$IN_USE_MINUTES" --argjson booted "$booted" -f "$SCRIPT_DIR/jq/old-runtimes.jq" 2>/dev/null
}

list() {
  local i changed="" temp=() sizes="" units sim=null out runtimes='{}' devices
  load_units
  check_units
  # A unit in use is never counted, so only the others get a du. Thousands of
  # temp folders share one find and one du through xargs (the argument limit):
  # a few processes per unit take minutes there. -prune stops at the first
  # changed folder, enough to put its unit in use. The other units stop at the
  # first changed file instead, which saves walking a big busy cache. du -l
  # counts a hard-linked file in every unit that holds it.
  for i in "${!paths[@]}"; do
    if [ "${ids[i]}" = tmpdir-temp ]; then
      temp+=("${paths[i]}")
    elif in_use "${paths[i]}"; then
      changed+=${paths[i]}$NL
    fi
  done
  if [ "${#temp[@]}" -gt 0 ]; then
    changed+=$(printf '%s\0' "${temp[@]}" | xargs -0 -J % find % -mmin "-$IN_USE_MINUTES" -print -prune 2>/dev/null || true)
  fi
  if [ "${#paths[@]}" -gt 0 ]; then
    sizes=$(printf '%s\0' "$changed" "${paths[@]}" | "$JQ" -Rsj --arg mode idle -f "$SCRIPT_DIR/jq/leftover-units.jq" | xargs -0 du -skl 2>/dev/null || true)
  fi
  units=$({
    printf '%s\0' "$changed" "$sizes" "$guard_rc" "$guard_err"
    for i in "${!paths[@]}"; do printf '%s\0' "${ids[i]}" "${paths[i]}"; done
  } | "$JQ" -Rsc --arg mode units -f "$SCRIPT_DIR/jq/leftover-units.jq")
  # Without developer tools, xcrun opens an install dialog instead of failing.
  if xcode-select -p >/dev/null 2>&1; then
    if [ "$MAX" = 1 ] && out=$(old_runtimes); then
      sim=$(printf '%s\n' "$out" | "$JQ" -Rnc '[inputs | select(. != "") | "Would delete " + .]')
    elif [ "$MAX" = 0 ] && out=$(xcrun simctl runtime delete --notUsedSinceDays "$UNUSED_DAYS" --dry-run 2>/dev/null); then
      sim=$(printf '%s\n' "$out" | "$JQ" -Rnc '[inputs | select(. != "")]')
    fi
  fi
  if [ "$sim" != null ]; then
    runtimes=$(xcrun simctl runtime list -j 2>/dev/null | "$JQ" -c 'objects' 2>/dev/null) || runtimes='{}'
    [ -n "$runtimes" ] || runtimes='{}'
  fi
  devices=$(old_devices) || devices=null
  printf '%s' "$units" | "$JQ" -sc --arg restart "$(restart_kb)" --argjson sim "$sim" --argjson runtimes "$runtimes" --argjson devices "$devices" -f "$SCRIPT_DIR/jq/leftovers.jq"
}

# Through stdin: thousands of paths overflow the argument list.
json_array() { if [ $# -gt 0 ]; then printf '%s\0' "$@"; fi | "$JQ" -Rsc 'split("\u0000")[:-1]'; }

remove() {
  local id i=0 p why err removed=() skipped=() errors=() sim=0 devices=0 out udid udids=() deleted
  [ $# -gt 0 ] || usage
  for id in "$@"; do
    if [ "$id" = simulator-runtimes ]; then
      sim=1
    elif [ "$id" = simulator-devices ]; then
      devices=1
    elif [[ $id == *"$NL"* ]] || ! catalog | cut -d'|' -f1 | grep -qxF -- "$id"; then
      echo "leftovers.sh: unknown id: $id" >&2
      exit 2
    fi
  done
  load_units "$@"
  check_units
  while [ "$i" -lt "${#paths[@]}" ]; do
    id=${ids[i]} p=${paths[i]}
    i=$((i + 1))
    why=$(refusal "$p")
    if [ -n "$why" ]; then
      skipped+=("$p" "$why")
      continue
    fi
    if in_use "$p"; then
      skipped+=("$p" "in use (changed in the last $IN_USE_MINUTES minutes)")
      continue
    fi
    # git keeps a record of each worktree; rm would leave it pointing nowhere.
    if [ "$id" = git-worktrees ]; then
      err=$(git_quiet -C "$p" worktree remove -- "$p" 2>&1) || errors+=("$p: ${err%%"$NL"*}")
      [ -e "$p" ] || removed+=("$p")
    elif err=$(rm -rf -- "$p" 2>&1); then
      removed+=("$p")
    else
      errors+=("$p: ${err%%"$NL"*}")
    fi
  done
  if [ "$sim" = 1 ]; then
    if ! xcode-select -p >/dev/null 2>&1; then
      errors+=("simulator-runtimes: developer tools are not installed")
    elif [ "$MAX" = 1 ]; then
      if ! out=$(old_runtimes); then
        errors+=("simulator-runtimes: simctl could not list runtimes")
      else
        # Nothing old to delete is neither removed nor an error.
        deleted=0
        while IFS=' ' read -r udid _; do
          [ -n "$udid" ] || continue
          if err=$(xcrun simctl runtime delete "$udid" 2>&1); then
            deleted=1
          else
            errors+=("simulator-runtimes: $udid: ${err%%"$NL"*}")
          fi
        done <<<"$out"
        [ "$deleted" = 0 ] || removed+=(simulator-runtimes)
      fi
    elif err=$(xcrun simctl runtime delete --notUsedSinceDays "$UNUSED_DAYS" 2>&1); then
      removed+=(simulator-runtimes)
    elif [[ $err != "No matching images found"* ]]; then
      errors+=("simulator-runtimes: ${err%%"$NL"*}")
    fi
  fi
  if [ "$devices" = 1 ]; then
    if ! xcode-select -p >/dev/null 2>&1; then
      errors+=("simulator-devices: developer tools are not installed")
    elif ! out=$(old_devices | "$JQ" -r '.[] | .udid, .dataPath'); then
      errors+=("simulator-devices: simctl could not list devices")
    else
      # simctl delete removes the device folder that holds data/; it goes
      # through guard.sh like any unit.
      paths=() ids=() guard_rc=0 guard_err=""
      while IFS= read -r udid && IFS= read -r p; do
        udids+=("$udid")
        paths+=("${p%/*}")
      done <<<"$out"
      check_units
      deleted=0
      for i in "${!paths[@]}"; do
        why=$(refusal "${paths[i]}")
        if [ -n "$why" ]; then
          skipped+=("${paths[i]}" "$why")
        elif in_use "${paths[i]}"; then
          skipped+=("${paths[i]}" "in use (changed in the last $IN_USE_MINUTES minutes)")
        elif err=$(xcrun simctl delete "${udids[i]}" 2>&1); then
          deleted=1
        else
          errors+=("simulator-devices: ${udids[i]}: ${err%%"$NL"*}")
        fi
      done
      [ "$deleted" = 0 ] || removed+=(simulator-devices)
    fi
  fi
  {
    json_array ${removed[@]+"${removed[@]}"}
    json_array ${skipped[@]+"${skipped[@]}"}
    json_array ${errors[@]+"${errors[@]}"}
  } | "$JQ" -sc '.[1] as $s | {removed: .[0], skipped: [range(0; $s | length; 2) as $k | {path: $s[$k], reason: $s[$k + 1]}], errors: .[2]}'
}

cmd=${1:-}
if [ $# -gt 0 ]; then shift; fi
if [ "${1:-}" = --max ]; then
  MAX=1
  shift
fi
case $cmd in
  list) [ $# -eq 0 ] || usage && list ;;
  remove) remove "$@" ;;
  *) usage ;;
esac
