#!/bin/bash
# Refuses paths that touch protected locations and fills Mole's whitelists with
# them.
# shellcheck disable=SC2088,SC2016 # "~" and '$HOME' patterns match literal text on purpose
set -Eeuo pipefail
# Exit codes are 0, 2 or 3 only: any unexpected failure means "could not check".
trap 'exit 2' ERR

if [ -z "${HOME:-}" ]; then
  echo "guard.sh: HOME is not set" >&2
  exit 2
fi
CONFIG="$HOME/.config/mole"
WHITELIST="$CONFIG/whitelist"
OPTIMIZE="$CONFIG/whitelist_optimize"
OPTIMIZE_LEGACY="$CONFIG/whitelist_checks"
PERMISSIONS_TASK=disk_permissions_repair
NL=$'\n'

usage() {
  echo "usage: guard.sh check [--allow-app <bundle-id>] <path>... | uninstall-check --allow-app <bundle-id> | whitelist | list" >&2
  exit 2
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Apple bundle ids: letters, digits, hyphens, at least two dot-separated parts.
valid_id() {
  case $1 in
    "" | .* | *. | *..* | *[!A-Za-z0-9.-]*) return 1 ;;
    *.*) return 0 ;;
    *) return 1 ;;
  esac
}

# resolve <absolute path>: the physical path, following symlinks even when the
# target or a trailing part is missing. realpath also gives the stored letter
# case, which bash's own `cd -P` does not. Fails on a symlink loop.
hops=0
resolve() {
  local p=$1 target parent
  if [ -L "$p" ]; then
    hops=$((hops + 1))
    [ "$hops" -le 40 ] || return 1
    target=$(readlink "$p")
    if [ "${target:0:1}" != / ]; then target="$(dirname "$p")/$target"; fi
    resolve "$target"
  elif [ -e "$p" ]; then
    realpath "$p"
  else
    parent=$(dirname "$p") && parent=$(resolve "$parent") || return 1
    case $(basename "$p") in
      ..) dirname "$parent" ;;
      .) echo "$parent" ;;
      *) echo "${parent%/}/$(basename "$p")" ;;
    esac
  fi
}

pictures_unreadable() { [ -d "$HOME/Pictures" ] && ! ls "$HOME/Pictures" >/dev/null 2>&1; }

builtins() {
  local p
  echo "$HOME/Library/Containers"
  for p in "$HOME"/Pictures/*.photoslibrary; do
    if [ -e "$p" ]; then echo "$p"; fi
  done
}

# whitelist_entry <line>: the line as Mole reads it (trimmed, ~ and $HOME
# expanded); fails for comments, blanks, `..`, the sentinel and non-paths.
whitelist_entry() {
  local line=$1
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  case $line in
    "~" | "~/"*) line="$HOME${line#\~}" ;;
  esac
  line="${line//\$\{HOME\}/$HOME}"
  line="${line//\$HOME/$HOME}"
  case $line in
    *..*) return 1 ;;
    /*) echo "$line" ;;
    *) return 1 ;;
  esac
}

rules=()
rule_lc=()
names=()
globs=()

# add_rule <path or glob> <1 if glob> [note]. A glob is kept as the resolved
# fixed part before its first wildcard and matched as a prefix.
add_rule() {
  local r fixed dir
  if [ "$2" = 1 ]; then
    fixed=${1%%[*?[]*}
    dir=${fixed%/*}
    r=$(resolve "${dir:-/}") || r=${dir:-/}
    r="${r%/}/${fixed##*/}"
  else
    r=$(resolve "$1") || r=$1
  fi
  rules+=("$r")
  rule_lc+=("$(lower "$r")")
  names+=("$1${3:-}")
  globs+=("$2")
}

# config_files: exits 2 when a Mole whitelist path exists but is not a regular
# file; Mole then ignores it, and a write would land inside it.
config_files() {
  local f
  for f in "$WHITELIST" "$OPTIMIZE" "$OPTIMIZE_LEGACY"; do
    if { [ -e "$f" ] || [ -L "$f" ]; } && [ ! -f "$f" ]; then
      echo "guard.sh: $f is not a regular file; move it aside and run again" >&2
      exit 2
    fi
  done
  # A folder on the way that cannot be searched hides the whitelist, which would
  # then read as absent and fall back to Mole's defaults.
  f=$CONFIG
  while [ ! -e "$f" ]; do f=$(dirname "$f"); done
  if [ ! -x "$f" ]; then
    echo "guard.sh: $f cannot be searched; cannot read Mole's whitelist" >&2
    exit 2
  fi
}

# Rule 0 is always ~/Library/Containers. Without a whitelist file Mole
# protects its default list, so that list is loaded instead.
load_rules() {
  local p line content
  config_files
  while IFS= read -r p; do add_rule "$p" 0; done <<<"$(builtins)"
  if pictures_unreadable; then add_rule "$HOME/Pictures" 0 " (unreadable)"; fi
  if [ -f "$WHITELIST" ]; then
    content=$(cat "$WHITELIST")
  else
    content=$(default_whitelist) || exit 2
  fi
  while IFS= read -r line; do
    if p=$(whitelist_entry "$line"); then
      case $p in
        *[*?[]*) add_rule "$p" 1 ;;
        *) add_rule "$p" 0 ;;
      esac
    fi
  done <<<"$content"
}

# refusal <path> <bundle-id or empty>: prints why the path is refused, or
# nothing. A path is refused when it equals, is inside, or is a parent of a
# rule; the picked app's containers are exempt from rules covering Containers.
refusal() {
  local p=$1 id=$2 r pl rl cl hit in_app=0 i=0
  case $p in
    "") echo "empty path" && return 0 ;;
    "~" | "~/"*) p="$HOME${p#\~}" ;;
  esac
  if [ "${p:0:1}" != / ]; then echo "relative path" && return 0; fi
  r=$(resolve "$p") || { echo "symlink loop" && return 0; }
  if [ "$r" = / ]; then echo root && return 0; fi
  # The kernel reads /.nofollow/<path> as <path>; realpath keeps the prefix.
  case $r in /.nofollow/*) echo "/.nofollow alias" && return 0 ;; esac
  pl=$(lower "$r")
  cl=${rule_lc[0]}
  if [ -n "$id" ]; then
    id=$(lower "$id")
    case $pl in
      "$cl/$id" | "$cl/$id"/* | "$cl/$id".*) in_app=1 ;;
    esac
  fi
  while [ "$i" -lt "${#rules[@]}" ]; do
    rl=${rule_lc[i]}
    hit=""
    case $pl in
      "$rl" | "$rl"/*) hit=inside ;;
    esac
    if [ "${globs[i]}" = 1 ]; then
      case $pl in
        "$rl"*) hit=inside ;;
      esac
    fi
    case $rl in
      "$pl"/*) hit=parent ;;
    esac
    if [ "$hit" = inside ] && [ "$in_app" = 1 ]; then
      case $cl in
        "$rl" | "$rl"/*) hit="" ;;
      esac
    fi
    if [ -n "$hit" ]; then echo "protected by ${names[i]}" && return 0; fi
    i=$((i + 1))
  done
}

check() {
  local id="" p why bad=0
  if [ "${1:-}" = --allow-app ]; then
    if [ $# -lt 2 ] || ! valid_id "$2"; then usage; fi
    id=$2
    shift 2
  fi
  [ $# -gt 0 ] || usage
  load_rules
  for p in "$@"; do
    why=$(refusal "$p" "$id")
    if [ -n "$why" ]; then
      echo "refused: ${p:-''} ($why)" >&2
      bad=1
    fi
  done
  [ "$bad" = 0 ] || exit 3
}

# Reads `mo uninstall --dry-run` text: drops ANSI codes, the leading icon, the
# `System:` / `Review only:` prefix and the `, <size>` suffix. Bytes (C locale)
# so an odd character never makes sed skip a line.
strip_preview() {
  local esc=$'\033' cr=$'\r'
  local strip="s/$esc\\[[0-9;]*[A-Za-z]//g; s/$cr+\$//; s/^[[:space:]]+//; s/^[^~/[:space:]]+[[:space:]]+//"
  strip="$strip; s/^(System|Review only): //; s/ , [0-9.]+[KMGT]?B\$//"
  LC_ALL=C sed -E "$strip"
}

# preview_paths <stripped preview>: its absolute paths, ~ expanded, one a line.
preview_paths() {
  local line
  while IFS= read -r line; do
    case $line in
      "~" | "~/"*) echo "$HOME${line#\~}" ;;
      /*) echo "$line" ;;
    esac
  done <<<"$1"
}

# uninstall-check --allow-app <id> [--shown <file>] [--preview <file>]: reads
# the preview from --preview, else stdin. With --shown, that preview (taken
# right before the real uninstall) may list only paths that <file>, the
# preview the owner saw, listed.
uninstall_check() {
  local id="" shown="" input=/dev/stdin preview line paths=()
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --allow-app) id=$2 ;;
      --shown) shown=$2 ;;
      --preview) input=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  valid_id "$id" || usage
  preview=$(strip_preview <"$input")
  # Mole removes a cask with `brew uninstall --cask [--zap]`, whose paths the
  # preview never lists (Mole lib/uninstall/batch.sh, brew_uninstall_cask).
  case $preview in
    *" [Brew]"*)
      echo "refused: Homebrew cask (brew removes paths the preview does not list; use brew uninstall --cask yourself)" >&2
      exit 3
      ;;
  esac
  while IFS= read -r line; do
    if [ -n "$line" ]; then paths+=("$line"); fi
  done <<<"$(preview_paths "$preview")"
  if [ "${#paths[@]}" -eq 0 ]; then
    echo "guard.sh: no path found in the uninstall preview" >&2
    exit 2
  fi
  if [ -n "$shown" ]; then
    local seen bad=0
    seen=$(preview_paths "$(strip_preview <"$shown")")
    if [ -z "$seen" ]; then
      echo "guard.sh: no path found in the shown preview $shown" >&2
      exit 2
    fi
    for line in "${paths[@]}"; do
      if ! grep -qxF -- "$line" <<<"$seen"; then
        echo "refused: $line (not in the preview shown)" >&2
        bad=1
      fi
    done
    [ "$bad" = 0 ] || exit 3
  fi
  check --allow-app "$id" "${paths[@]}"
}

# First hit wins: $DISKDIET_MOLE_LIB, the lib next to the SCRIPT_DIR pinned in
# the resolved launcher, the lib next to the resolved launcher, Mole's
# install.sh location.
mole_lib() {
  local launcher="" pinned="" d
  if launcher=$(command -v mo); then
    launcher=$(realpath "$launcher")
    pinned=$(sed -n 's|^SCRIPT_DIR="\(/[^"$]*\)"$|\1|p' "$launcher" | head -n 1)
  fi
  for d in "${DISKDIET_MOLE_LIB:-}" "${pinned:+$pinned/lib}" "${launcher:+$(dirname "$launcher")/lib}" "$CONFIG/lib"; do
    if [ -n "$d" ] && [ -f "$d/core/base.sh" ]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

# mole_defaults <base.sh>: DEFAULT_WHITELIST_PATTERNS, one line each, as Mole
# would write them. Fails unless every entry is a quoted plain $HOME path or
# the sentinel.
mole_defaults() {
  local line rest on=0 n=0
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [ "$on" = 0 ]; then
      if [ "$line" = "declare -a DEFAULT_WHITELIST_PATTERNS=(" ]; then on=1; fi
      continue
    fi
    case $line in
      ")")
        if [ "$n" -gt 0 ]; then return 0; fi
        return 1
        ;;
      "" | "#"*) continue ;;
      '"$FINDER_METADATA_SENTINEL"') echo FINDER_METADATA ;;
      '"$HOME/'*'"')
        rest=${line#\"\$HOME/}
        rest=${rest%\"}
        case $rest in
          *[\"\$\`\\]*) return 1 ;;
        esac
        echo "\$HOME/$rest"
        ;;
      *) return 1 ;;
    esac
    n=$((n + 1))
  done <<<"$(cat "$1")"
  return 1
}

# default_whitelist: Mole's default whitelist lines; exits 2 with the reason
# when its source cannot be found or parsed.
default_whitelist() {
  local lib
  lib=$(mole_lib) || {
    echo "guard.sh: Mole source not found; cannot read its default whitelist" >&2
    exit 2
  }
  mole_defaults "$lib/core/base.sh" || {
    echo "guard.sh: cannot parse DEFAULT_WHITELIST_PATTERNS in $lib/core/base.sh" >&2
    exit 2
  }
}

added=()
tmp=""
trap '[ -z "$tmp" ] || rm -f "$tmp"' EXIT

# write_lines <file> <current content> <line>...: appends the lines the content
# lacks and replaces <file> atomically (temp file, then mv).
write_lines() {
  local file=$1 content=$2 line before=${#added[@]}
  shift 2
  for line in "$@"; do
    if ! grep -qxF -- "$line" <<<"$content"; then
      content="${content:+$content$NL}$line"
      added+=("$line")
    fi
  done
  [ "${#added[@]}" -gt "$before" ] || return 0
  tmp=$(mktemp "$file.XXXXXX")
  printf '%s\n' "$content" >"$tmp"
  mv "$tmp" "$file"
  tmp=""
}

# optimize_tasks: every `mo optimize` action with the $HOME paths it rewrites or
# removes (Mole 1.56.1 lib/optimize/tasks.sh), one `action|path` line each; an
# action that changes no user file has an empty path. Mole checks its path
# whitelist in none of them but fix_broken_configs.
optimize_tasks() {
  cat <<'TASKS'
system_maintenance|
cache_refresh|$HOME/Library/Caches/com.apple.iconservices
cache_refresh|$HOME/Library/Caches/com.apple.iconservices.store
cache_refresh|$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache
saved_state_cleanup|$HOME/Library/Saved Application State
fix_broken_configs|$HOME/Library/Preferences
network_optimization|
sqlite_vacuum|$HOME/Library/Mail
sqlite_vacuum|$HOME/Library/Messages
sqlite_vacuum|$HOME/Library/Safari
prevent_network_dsstore|$HOME/Library/Preferences/com.apple.desktopservices.plist
legacy_overrides_audit|$HOME/Library/Preferences/.GlobalPreferences.plist
legacy_overrides_audit|$HOME/Library/Preferences/com.apple.frameworks.diskimages.plist
network_stack_optimize|
disk_permissions_repair|
spotlight_index_optimize|
spotlight_orphan_rules_cleanup|$HOME/Library/Preferences/com.apple.spotlight.plist
periodic_maintenance|
shared_file_list_repair|$HOME/Library/Application Support/com.apple.sharedfilelist
disk_verify|
login_items_audit|
quarantine_cleanup|$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2
launch_agents_cleanup|$HOME/Library/LaunchAgents
notification_cleanup|$HOME/Library/Group Containers/group.com.apple.usernoted
coreduet_cleanup|$HOME/Library/Application Support/Knowledge
TASKS
}

# excluded_tasks: the optimize actions whose paths a rule protects.
excluded_tasks() {
  local task p
  load_rules
  while IFS='|' read -r task p; do
    if [ -n "$p" ] && [ -n "$(refusal "$HOME${p#\$HOME}" "")" ]; then echo "$task"; fi
  done <<<"$(optimize_tasks)"
}

whitelist() {
  local content="" p r wanted=() tasks=()
  config_files
  if pictures_unreadable; then
    echo "guard.sh: $HOME/Pictures is not readable (grant Full Disk Access to the terminal); Photos libraries cannot be protected" >&2
    exit 2
  fi
  if [ -f "$WHITELIST" ]; then
    content=$(cat "$WHITELIST")
  else
    # A whitelist file replaces Mole's defaults, so a new one starts with them.
    content=$(default_whitelist) || exit 2
  fi
  # Mole compares plain strings, so write the $HOME form and the resolved form.
  while IFS= read -r p; do
    wanted+=("\$HOME${p#"$HOME"}")
    r=$(resolve "$p") || r=$p
    if [ "$r" != "$p" ]; then wanted+=("$r"); fi
  done <<<"$(builtins)"
  mkdir -p "$CONFIG"
  write_lines "$WHITELIST" "$content" "${wanted[@]}"
  while IFS= read -r p; do
    if [ -n "$p" ]; then tasks+=("$p"); fi
  done <<<"$(excluded_tasks)"
  # Mole reads the legacy file only while whitelist_optimize is absent.
  content=""
  if [ -f "$OPTIMIZE" ]; then
    content=$(cat "$OPTIMIZE")
  elif [ -f "$OPTIMIZE_LEGACY" ]; then
    content=$(cat "$OPTIMIZE_LEGACY")
  fi
  write_lines "$OPTIMIZE" "$content" "$PERMISSIONS_TASK" ${tasks[@]+"${tasks[@]}"}
  if [ "${#added[@]}" -eq 0 ]; then
    echo "[]"
  else
    printf '%s\n' "${added[@]}" | jq -Rnc '[inputs]'
  fi
}

# Concrete paths only: globs and the sentinel cannot be counted or checked.
list() {
  local i=0
  load_rules
  while [ "$i" -lt "${#rules[@]}" ]; do
    if [ "${globs[i]}" = 0 ]; then echo "${rules[i]}"; fi
    i=$((i + 1))
  done | awk '!seen[$0]++' | jq -Rnc '[inputs]'
}

command -v jq >/dev/null 2>&1 || {
  echo "guard.sh: jq is required" >&2
  exit 2
}

cmd=${1:-}
if [ $# -gt 0 ]; then shift; fi
case $cmd in
  check) check "$@" ;;
  uninstall-check) uninstall_check "$@" ;;
  whitelist) whitelist ;;
  list) list ;;
  *) usage ;;
esac
