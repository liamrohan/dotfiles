#!/usr/bin/env bash

set -u -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$SCRIPT_DIR/install.sh"

TARGET_DIR="${HOME:-}"
DRY_RUN=0
LIST_ONLY=0

# Keep this focused: core Omarchy desktop/look-and-feel components only.
PACKAGES=(
  omarchy
  hypr
  hyprland-preview-share-picker
  waybar
  walker
  swayosd
  uwsm
  mako
)

usage() {
  cat <<'EOF'
Usage: ./install-minimal.sh [options]

Install minimal Omarchy-related configs using install.sh.

Options:
  -t, --target <dir>   Target directory (default: $HOME)
  -n, --dry-run        Preview only
      --list           Print package list and exit
  -h, --help           Show this help
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

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--target)
        [[ $# -lt 2 ]] && { err "Missing value for $1"; exit 2; }
        TARGET_DIR="$2"
        shift 2
        ;;
      -n|--dry-run)
        DRY_RUN=1
        shift
        ;;
      --list)
        LIST_ONLY=1
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

main() {
  local -a selected=()
  local -a cmd=()
  local pkg=""

  parse_args "$@"

  if [[ ! -f "$INSTALLER" ]]; then
    err "Required installer not found: $INSTALLER"
    exit 1
  fi

  if [[ -z "$TARGET_DIR" ]]; then
    err "HOME is not set. Provide --target <dir>."
    exit 1
  fi

  for pkg in "${PACKAGES[@]}"; do
    if [[ -d "$SCRIPT_DIR/$pkg" ]]; then
      selected+=("$pkg")
    else
      warn "Package missing in repo, skipping: $pkg"
    fi
  done

  if [[ ${#selected[@]} -eq 0 ]]; then
    err "No minimal packages found in repo."
    exit 1
  fi

  if (( LIST_ONLY == 1 )); then
    printf '%s\n' "${selected[@]}"
    exit 0
  fi

  log "Installing minimal Omarchy config set to: $TARGET_DIR"
  log "Packages: ${selected[*]}"

  cmd=(bash "$INSTALLER" --target "$TARGET_DIR")
  (( DRY_RUN == 1 )) && cmd+=(--dry-run)
  for pkg in "${selected[@]}"; do
    cmd+=(--package "$pkg")
  done

  "${cmd[@]}"
}

main "$@"
