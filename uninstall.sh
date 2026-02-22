#!/usr/bin/env bash

set -u -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

TARGET_DIR="${HOME:-}"
BACKUP_ROOT=""
DRY_RUN=0
DO_UNSTOW=1
VERBOSE=1
TIMESTAMP_FILTER=""

declare -a ONLY_PACKAGES=()
declare -a EXCLUDE_PACKAGES=()

declare -a UNSTOWED=()
declare -a SKIPPED_EXCLUDED=()
declare -a SKIPPED_NOT_FOUND=()
declare -a FAILED_UNSTOW=()

declare -a RESTORED=()
declare -a SKIPPED_COLLISION=()
declare -a SKIPPED_MISSING=()
declare -a FAILED_RESTORE=()
declare -a SKIPPED_MALFORMED=()
declare -a SKIPPED_FILTERED=()
declare -a SELECTED_BACKUPS=()

declare -A RESTORE_SOURCE_BY_ORIGINAL=()
declare -A RESTORE_TIMESTAMP_BY_ORIGINAL=()
declare -A RESTORE_INDEX_BY_ORIGINAL=()

PARSED_ORIGINAL=""
PARSED_SUFFIX=""
PARSED_TIMESTAMP=""
PARSED_INDEX=""

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [options]

Undo install.sh changes by unstowing packages and restoring backup files.

Options:
  -t, --target <dir>       Target directory (default: $HOME)
  -p, --package <name>     Unstow only this package (repeatable)
  -x, --exclude <name>     Exclude this package (repeatable)
  -n, --dry-run            Preview actions only
      --no-unstow          Skip unstow; only restore backups
      --restore-only       Alias for --no-unstow
      --backup-root <dir>  Directory tree to scan for backups (default: target)
      --timestamp <prefix> Restore only backups whose suffix starts with prefix
  -q, --quiet              Less stow output
  -h, --help               Show help

Examples:
  ./uninstall.sh
  ./uninstall.sh --dry-run
  ./uninstall.sh --restore-only --timestamp 20260221
  ./uninstall.sh --package hypr --package waybar
EOF
}

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

err() {
  printf '[ERROR] %s\n' "$*" >&2
}

contains_item() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

discover_packages() {
  find "$REPO_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | sort \
    | awk '$1 != ".git" && $1 !~ /^\./'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--target)
        [[ $# -lt 2 ]] && { err "Missing value for $1"; exit 2; }
        TARGET_DIR="$2"
        shift 2
        ;;
      -p|--package)
        [[ $# -lt 2 ]] && { err "Missing value for $1"; exit 2; }
        ONLY_PACKAGES+=("$2")
        shift 2
        ;;
      -x|--exclude)
        [[ $# -lt 2 ]] && { err "Missing value for $1"; exit 2; }
        EXCLUDE_PACKAGES+=("$2")
        shift 2
        ;;
      -n|--dry-run)
        DRY_RUN=1
        shift
        ;;
      --no-unstow|--restore-only)
        DO_UNSTOW=0
        shift
        ;;
      --backup-root)
        [[ $# -lt 2 ]] && { err "Missing value for $1"; exit 2; }
        BACKUP_ROOT="$2"
        shift 2
        ;;
      --timestamp)
        [[ $# -lt 2 ]] && { err "Missing value for $1"; exit 2; }
        TIMESTAMP_FILTER="$2"
        shift 2
        ;;
      -q|--quiet)
        VERBOSE=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unknown argument: $1"
        usage
        exit 2
        ;;
    esac
  done
}

run_unstow_for_package() {
  local pkg="$1"
  local -a base_args=()
  local output=""

  base_args=(--dir "$REPO_DIR" --target "$TARGET_DIR")
  (( VERBOSE == 1 )) && base_args+=(-v)

  if (( DRY_RUN == 1 )); then
    if output="$(stow "${base_args[@]}" -n -D "$pkg" 2>&1)"; then
      log "Dry-run unstow OK: $pkg"
      UNSTOWED+=("$pkg")
      return 0
    fi
    warn "Unstow preview failed for '$pkg'."
    FAILED_UNSTOW+=("$pkg")
    printf '%s\n' "$output" >&2
    return 0
  fi

  if output="$(stow "${base_args[@]}" -D "$pkg" 2>&1)"; then
    log "Unstowed: $pkg"
    UNSTOWED+=("$pkg")
    return 0
  fi

  warn "Unstow failed for '$pkg'."
  FAILED_UNSTOW+=("$pkg")
  printf '%s\n' "$output" >&2
  return 0
}

parse_backup_path() {
  local path="$1"

  PARSED_ORIGINAL=""
  PARSED_SUFFIX=""
  PARSED_TIMESTAMP=""
  PARSED_INDEX=""

  if [[ "$path" =~ ^(.*)\.bak\.([0-9]{14})(\.([0-9]+))?$ ]]; then
    PARSED_ORIGINAL="${BASH_REMATCH[1]}"
    PARSED_TIMESTAMP="${BASH_REMATCH[2]}"
    PARSED_INDEX="${BASH_REMATCH[4]:-0}"
    PARSED_SUFFIX="$PARSED_TIMESTAMP"
    if [[ -n "${BASH_REMATCH[4]:-}" ]]; then
      PARSED_SUFFIX="${PARSED_SUFFIX}.${BASH_REMATCH[4]}"
    fi
    return 0
  fi

  return 1
}

candidate_is_older() {
  local cand_ts="$1"
  local cand_idx="$2"
  local cur_ts="$3"
  local cur_idx="$4"

  if [[ "$cand_ts" < "$cur_ts" ]]; then
    return 0
  fi
  if [[ "$cand_ts" > "$cur_ts" ]]; then
    return 1
  fi

  (( 10#$cand_idx < 10#$cur_idx ))
}

scan_backups() {
  local path=""
  local original=""
  local selected_ts=""
  local selected_idx=""

  while IFS= read -r -d '' path; do
    if ! parse_backup_path "$path"; then
      warn "Skipping malformed backup name: $path"
      SKIPPED_MALFORMED+=("$path")
      continue
    fi

    if [[ -n "$TIMESTAMP_FILTER" && "$PARSED_SUFFIX" != "$TIMESTAMP_FILTER"* ]]; then
      SKIPPED_FILTERED+=("$path")
      continue
    fi

    original="$PARSED_ORIGINAL"
    if [[ -z "${RESTORE_SOURCE_BY_ORIGINAL[$original]+x}" ]]; then
      RESTORE_SOURCE_BY_ORIGINAL["$original"]="$path"
      RESTORE_TIMESTAMP_BY_ORIGINAL["$original"]="$PARSED_TIMESTAMP"
      RESTORE_INDEX_BY_ORIGINAL["$original"]="$PARSED_INDEX"
      continue
    fi

    selected_ts="${RESTORE_TIMESTAMP_BY_ORIGINAL[$original]}"
    selected_idx="${RESTORE_INDEX_BY_ORIGINAL[$original]}"

    if candidate_is_older "$PARSED_TIMESTAMP" "$PARSED_INDEX" "$selected_ts" "$selected_idx"; then
      RESTORE_SOURCE_BY_ORIGINAL["$original"]="$path"
      RESTORE_TIMESTAMP_BY_ORIGINAL["$original"]="$PARSED_TIMESTAMP"
      RESTORE_INDEX_BY_ORIGINAL["$original"]="$PARSED_INDEX"
    fi
  done < <(find "$BACKUP_ROOT" -mindepth 1 -name '*.bak.*' -print0 2>/dev/null)
}

restore_backups() {
  local -a originals=()
  local original=""
  local backup=""
  local parent=""

  if [[ ${#RESTORE_SOURCE_BY_ORIGINAL[@]} -eq 0 ]]; then
    log "No backups selected for restore."
    return 0
  fi

  mapfile -t originals < <(printf '%s\n' "${!RESTORE_SOURCE_BY_ORIGINAL[@]}" | sort)
  for original in "${originals[@]}"; do
    backup="${RESTORE_SOURCE_BY_ORIGINAL[$original]}"
    SELECTED_BACKUPS+=("$backup")

    if [[ ! -e "$backup" && ! -L "$backup" ]]; then
      warn "Selected backup is missing: $backup"
      SKIPPED_MISSING+=("$backup")
      continue
    fi

    if [[ -e "$original" || -L "$original" ]]; then
      warn "Restore skipped (target exists): $original"
      SKIPPED_COLLISION+=("$original")
      continue
    fi

    if (( DRY_RUN == 1 )); then
      log "Would restore: $backup -> $original"
      RESTORED+=("$original")
      continue
    fi

    parent="$(dirname -- "$original")"
    if [[ ! -d "$parent" ]] && ! mkdir -p -- "$parent"; then
      warn "Failed to create parent directory for restore: $parent"
      FAILED_RESTORE+=("$backup")
      continue
    fi

    if mv -- "$backup" "$original"; then
      log "Restored: $backup -> $original"
      RESTORED+=("$original")
    else
      warn "Failed to restore backup: $backup"
      FAILED_RESTORE+=("$backup")
    fi
  done
}

main() {
  local -a discovered=()
  local -a selected=()
  local pkg=""

  parse_args "$@"

  if [[ -z "$TARGET_DIR" ]]; then
    err "HOME is not set. Provide --target <dir>."
    exit 2
  fi
  if [[ ! -d "$TARGET_DIR" ]]; then
    err "Target directory '$TARGET_DIR' does not exist."
    exit 1
  fi

  if [[ -z "$BACKUP_ROOT" ]]; then
    BACKUP_ROOT="$TARGET_DIR"
  fi
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    err "Backup root '$BACKUP_ROOT' does not exist."
    exit 1
  fi

  log "Repo:        $REPO_DIR"
  log "Target:      $TARGET_DIR"
  log "Backup root: $BACKUP_ROOT"
  (( DO_UNSTOW == 0 )) && log "Unstow:      disabled"
  (( DRY_RUN == 1 )) && log "Mode:        dry-run"
  [[ -n "$TIMESTAMP_FILTER" ]] && log "Timestamp filter: $TIMESTAMP_FILTER"

  if (( DO_UNSTOW == 1 )); then
    if ! command -v stow >/dev/null 2>&1; then
      err "GNU Stow is not installed."
      err "Install it first (e.g. Debian/Ubuntu: apt install stow, Arch: pacman -S stow)."
      exit 1
    fi

    mapfile -t discovered < <(discover_packages)
    if [[ ${#discovered[@]} -eq 0 ]]; then
      err "No stow packages found in '$REPO_DIR'."
      exit 1
    fi

    if [[ ${#ONLY_PACKAGES[@]} -gt 0 ]]; then
      for pkg in "${ONLY_PACKAGES[@]}"; do
        if contains_item "$pkg" "${discovered[@]}"; then
          selected+=("$pkg")
        else
          warn "Requested package not found: $pkg"
          SKIPPED_NOT_FOUND+=("$pkg")
        fi
      done
    else
      selected=("${discovered[@]}")
    fi

    if [[ ${#selected[@]} -eq 0 ]]; then
      err "No packages selected for unstow."
      exit 1
    fi

    for pkg in "${selected[@]}"; do
      if contains_item "$pkg" "${EXCLUDE_PACKAGES[@]}"; then
        warn "Excluded package: $pkg"
        SKIPPED_EXCLUDED+=("$pkg")
        continue
      fi
      run_unstow_for_package "$pkg"
    done
  else
    if [[ ${#ONLY_PACKAGES[@]} -gt 0 || ${#EXCLUDE_PACKAGES[@]} -gt 0 ]]; then
      warn "Package include/exclude filters are ignored because unstow is disabled."
    fi
  fi

  scan_backups
  restore_backups

  printf '\n=== Summary ===\n'
  printf 'Unstowed/OK:            %d\n' "${#UNSTOWED[@]}"
  printf 'Skipped (excluded):     %d\n' "${#SKIPPED_EXCLUDED[@]}"
  printf 'Skipped (not found):    %d\n' "${#SKIPPED_NOT_FOUND[@]}"
  printf 'Failed unstow:          %d\n' "${#FAILED_UNSTOW[@]}"
  printf 'Backups selected:       %d\n' "${#SELECTED_BACKUPS[@]}"
  printf 'Restored/Planned:       %d\n' "${#RESTORED[@]}"
  printf 'Skipped (collision):    %d\n' "${#SKIPPED_COLLISION[@]}"
  printf 'Skipped (missing):      %d\n' "${#SKIPPED_MISSING[@]}"
  printf 'Skipped (malformed):    %d\n' "${#SKIPPED_MALFORMED[@]}"
  printf 'Skipped (filter):       %d\n' "${#SKIPPED_FILTERED[@]}"
  printf 'Failed restore:         %d\n' "${#FAILED_RESTORE[@]}"

  if [[ ${#FAILED_UNSTOW[@]} -gt 0 ]]; then
    printf '\nPackages with unstow failures:\n'
    printf '  - %s\n' "${FAILED_UNSTOW[@]}"
  fi

  if [[ ${#SKIPPED_COLLISION[@]} -gt 0 ]]; then
    printf '\nRestore collisions (left untouched):\n'
    printf '  - %s\n' "${SKIPPED_COLLISION[@]}"
  fi

  if [[ ${#FAILED_RESTORE[@]} -gt 0 ]]; then
    printf '\nBackups with restore failures:\n'
    printf '  - %s\n' "${FAILED_RESTORE[@]}"
  fi

  if [[ ${#FAILED_UNSTOW[@]} -gt 0 || ${#FAILED_RESTORE[@]} -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
