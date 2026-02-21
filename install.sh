#!/usr/bin/env bash

set -u -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

TARGET_DIR="${HOME:-}"
DRY_RUN=0
RESTOW=1
VERBOSE=1
BACKUP_TIMESTAMP="$(date +%Y%m%d%H%M%S)"

declare -a ONLY_PACKAGES=()
declare -a EXCLUDE_PACKAGES=()

declare -a INSTALLED=()
declare -a SKIPPED_CONFLICT=()
declare -a SKIPPED_EXCLUDED=()
declare -a SKIPPED_NOT_FOUND=()
declare -a FAILED=()
declare -a BACKED_UP=()

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Install dotfiles packages with GNU Stow, one package at a time.
Conflicted targets are backed up and retried. If still conflicted, package is skipped.

Options:
  -t, --target <dir>      Target directory (default: $HOME)
  -p, --package <name>    Install only this package (repeatable)
  -x, --exclude <name>    Exclude this package (repeatable)
  -n, --dry-run           Preview actions only
      --no-restow         Do not use stow --restow
  -q, --quiet             Less stow output
  -h, --help              Show help

Examples:
  ./install.sh
  ./install.sh --dry-run
  ./install.sh --package hypr --package waybar
  ./install.sh --exclude nvim --exclude helix
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

is_conflict_output() {
  local out="$1"
  [[ "$out" == *"would cause conflicts"* ]] \
    || [[ "$out" == *"existing target is neither a link nor a directory"* ]] \
    || [[ "$out" == *"cannot stow"* ]] \
    || [[ "$out" == *"is not owned by stow"* ]] \
    || [[ "$out" == *"CONFLICT"* ]]
}

extract_conflict_targets() {
  local out="$1"
  printf '%s\n' "$out" | awk '
    /existing target / {
      line = $0
      sub(/^.*existing target /, "", line)
      sub(/ since .*/, "", line)
      sub(/ is neither a link nor a directory.*/, "", line)
      sub(/ is .*$/, "", line)
      sub(/ owned by .*$/, "", line)
      gsub(/^'\''|'\''$/, "", line)
      if (line != "") print line
    }
  ' | awk '!seen[$0]++'
}

backup_conflict_targets() {
  local out="$1"
  local mode="${2:-apply}"
  local moved=0
  local rel=""
  local src=""
  local backup=""
  local n=1
  local -a targets=()

  mapfile -t targets < <(extract_conflict_targets "$out")
  if [[ ${#targets[@]} -eq 0 ]]; then
    warn "Conflict detected but no target paths were parsed from stow output."
    return 1
  fi

  for rel in "${targets[@]}"; do
    if [[ "$rel" == /* ]]; then
      src="$rel"
    else
      src="$TARGET_DIR/$rel"
    fi

    if [[ ! -e "$src" && ! -L "$src" ]]; then
      warn "Conflict target missing, nothing to back up: $src"
      continue
    fi

    backup="${src}.bak.${BACKUP_TIMESTAMP}"
    n=1
    while [[ -e "$backup" || -L "$backup" ]]; do
      backup="${src}.bak.${BACKUP_TIMESTAMP}.${n}"
      ((n++))
    done

    if [[ "$mode" == "simulate" ]]; then
      log "Would back up: $src -> $backup"
      BACKED_UP+=("$backup")
      moved=1
      continue
    fi

    if mv -- "$src" "$backup"; then
      log "Backed up: $src -> $backup"
      BACKED_UP+=("$backup")
      moved=1
    else
      warn "Failed to back up conflict target: $src"
      return 1
    fi
  done

  (( moved == 1 ))
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
      --no-restow)
        RESTOW=0
        shift
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

run_stow_for_package() {
  local pkg="$1"
  local -a base_args=()
  local output=""
  local preview_attempt=0
  local install_attempt=0

  base_args=(--dir "$REPO_DIR" --target "$TARGET_DIR")
  (( VERBOSE == 1 )) && base_args+=(-v)
  (( RESTOW == 1 )) && base_args+=(-R)

  while :; do
    if output="$(stow "${base_args[@]}" -n "$pkg" 2>&1)"; then
      break
    fi

    if is_conflict_output "$output"; then
      if (( DRY_RUN == 1 )); then
        if backup_conflict_targets "$output" "simulate"; then
          log "Dry-run OK (simulated backups): $pkg"
          INSTALLED+=("$pkg")
          return 0
        fi

        warn "Skipping '$pkg' due to conflict during preview."
        SKIPPED_CONFLICT+=("$pkg")
        printf '%s\n' "$output" >&2
        return 0
      fi

      if (( preview_attempt == 0 )) && backup_conflict_targets "$output"; then
        preview_attempt=1
        warn "Retesting '$pkg' after conflict backups."
        continue
      fi

      warn "Skipping '$pkg' due to unresolved conflict."
      SKIPPED_CONFLICT+=("$pkg")
      printf '%s\n' "$output" >&2
      return 0
    fi

    warn "Skipping '$pkg' because preview failed."
    FAILED+=("$pkg")
    printf '%s\n' "$output" >&2
    return 0
  done

  if (( DRY_RUN == 1 )); then
    log "Dry-run OK: $pkg"
    INSTALLED+=("$pkg")
    return 0
  fi

  while :; do
    if output="$(stow "${base_args[@]}" "$pkg" 2>&1)"; then
      break
    fi

    if is_conflict_output "$output"; then
      if (( install_attempt == 0 )) && backup_conflict_targets "$output"; then
        install_attempt=1
        warn "Retrying '$pkg' after conflict backups."
        continue
      fi

      warn "Skipping '$pkg' due to conflict."
      SKIPPED_CONFLICT+=("$pkg")
      printf '%s\n' "$output" >&2
      return 0
    fi

    warn "Skipping '$pkg' because install failed."
    FAILED+=("$pkg")
    printf '%s\n' "$output" >&2
    return 0
  done

  log "Installed: $pkg"
  INSTALLED+=("$pkg")
  return 0
}

main() {
  local -a discovered=()
  local -a selected=()
  local pkg=""

  parse_args "$@"

  if ! command -v stow >/dev/null 2>&1; then
    err "GNU Stow is not installed."
    err "Install it first (e.g. Debian/Ubuntu: apt install stow, Arch: pacman -S stow)."
    exit 1
  fi

  if [[ -z "$TARGET_DIR" ]]; then
    err "HOME is not set. Provide --target <dir>."
    exit 1
  fi

  if [[ ! -d "$TARGET_DIR" ]]; then
    warn "Target directory '$TARGET_DIR' does not exist. Creating it."
    if ! mkdir -p "$TARGET_DIR"; then
      err "Failed to create target directory '$TARGET_DIR'."
      exit 1
    fi
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
    err "No packages selected."
    exit 1
  fi

  log "Repo:   $REPO_DIR"
  log "Target: $TARGET_DIR"
  (( DRY_RUN == 1 )) && log "Mode:   dry-run"

  for pkg in "${selected[@]}"; do
    if contains_item "$pkg" "${EXCLUDE_PACKAGES[@]}"; then
      warn "Excluded package: $pkg"
      SKIPPED_EXCLUDED+=("$pkg")
      continue
    fi
    run_stow_for_package "$pkg"
  done

  printf '\n=== Summary ===\n'
  printf 'Installed/OK:          %d\n' "${#INSTALLED[@]}"
  printf 'Skipped (conflicts):   %d\n' "${#SKIPPED_CONFLICT[@]}"
  printf 'Skipped (excluded):    %d\n' "${#SKIPPED_EXCLUDED[@]}"
  printf 'Skipped (not found):   %d\n' "${#SKIPPED_NOT_FOUND[@]}"
  printf 'Failed (other):        %d\n' "${#FAILED[@]}"
  if (( DRY_RUN == 1 )); then
    printf 'Backups planned:       %d\n' "${#BACKED_UP[@]}"
  else
    printf 'Backed up targets:     %d\n' "${#BACKED_UP[@]}"
  fi

  if [[ ${#SKIPPED_CONFLICT[@]} -gt 0 ]]; then
    printf '\nConflicted packages:\n'
    printf '  - %s\n' "${SKIPPED_CONFLICT[@]}"
  fi

  if [[ ${#FAILED[@]} -gt 0 ]]; then
    printf '\nFailed packages:\n'
    printf '  - %s\n' "${FAILED[@]}"
  fi

  if [[ ${#BACKED_UP[@]} -gt 0 ]]; then
    if (( DRY_RUN == 1 )); then
      printf '\nBackups planned (dry-run):\n'
    else
      printf '\nBackups created:\n'
    fi
    printf '  - %s\n' "${BACKED_UP[@]}"
  fi

  if [[ ${#FAILED[@]} -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
