#!/usr/bin/env bash

set -u -o pipefail

PROFILE="full"
DRY_RUN=0
ASSUME_YES=1
USE_AUR=1

declare -a INSTALLED=()
declare -a SKIPPED=()
declare -a NOT_FOUND=()
declare -a FAILED=()

usage() {
  cat <<'EOF'
Usage: ./install-apps.sh [options]

Install apps that correspond to this dotfiles repo (Arch Linux).

Options:
  --minimal            Install only the core Omarchy desktop app stack
  --full               Install the full mapped app stack (default)
  -n, --dry-run        Print what would be installed, do not install
  -y, --yes            Non-interactive (default)
      --no-aur         Skip AUR lookups/install attempts
  -h, --help           Show this help
EOF
}

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERROR] %s\n' "$*" >&2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --minimal) PROFILE="minimal"; shift ;;
      --full) PROFILE="full"; shift ;;
      -n|--dry-run) DRY_RUN=1; shift ;;
      -y|--yes) ASSUME_YES=1; shift ;;
      --no-aur) USE_AUR=0; shift ;;
      -h|--help) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage; exit 2 ;;
    esac
  done
}

require_arch() {
  if ! command -v pacman >/dev/null 2>&1; then
    err "This installer currently supports Arch Linux (pacman) only."
    exit 1
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

get_aur_helper() {
  if (( USE_AUR == 0 )); then
    return 1
  fi
  if have_cmd yay; then
    printf 'yay\n'
    return 0
  fi
  if have_cmd paru; then
    printf 'paru\n'
    return 0
  fi
  return 1
}

pacman_has_pkg() {
  local pkg="$1"
  pacman -Si "$pkg" >/dev/null 2>&1
}

aur_has_pkg() {
  local helper="$1"
  local pkg="$2"
  "$helper" -Si "$pkg" >/dev/null 2>&1
}

pkg_installed() {
  local pkg="$1"
  pacman -Q "$pkg" >/dev/null 2>&1
}

install_with_pacman() {
  local pkg="$1"
  local -a cmd=(pacman -S --needed)
  (( ASSUME_YES == 1 )) && cmd+=(--noconfirm)
  cmd+=("$pkg")

  if (( DRY_RUN == 1 )); then
    log "[dry-run] sudo ${cmd[*]}"
    INSTALLED+=("$pkg")
    return 0
  fi

  if (( EUID == 0 )); then
    "${cmd[@]}"
  else
    sudo "${cmd[@]}"
  fi
}

install_with_aur() {
  local helper="$1"
  local pkg="$2"
  local -a cmd=("$helper" -S --needed)
  (( ASSUME_YES == 1 )) && cmd+=(--noconfirm)
  cmd+=("$pkg")

  if (( DRY_RUN == 1 )); then
    log "[dry-run] ${cmd[*]}"
    INSTALLED+=("$pkg")
    return 0
  fi

  "${cmd[@]}"
}

# Optional fallback installers for tools that may not be packaged the same way.
install_optional_fallback() {
  local label="$1"

  case "$label" in
    snyk)
      if ! have_cmd npm; then
        return 1
      fi
      if have_cmd snyk; then
        log "Already installed (snyk): snyk"
        SKIPPED+=("snyk")
        return 0
      fi
      if (( DRY_RUN == 1 )); then
        log "[dry-run] npm install -g snyk"
        INSTALLED+=("snyk(npm)")
        return 0
      fi
      if npm install -g snyk; then
        INSTALLED+=("snyk(npm)")
        return 0
      fi
      return 1
      ;;
  esac

  return 1
}

# Tries candidate package names in order:
# 1) already installed
# 2) available in pacman repos
# 3) available in AUR helper
install_from_candidates() {
  local label="$1"
  local helper="${2:-}"
  local required="${3:-0}"
  shift 3
  local -a candidates=("$@")
  local pkg=""

  if [[ ${#candidates[@]} -eq 0 ]]; then
    warn "No candidates provided for $label"
    if (( required == 1 )); then
      FAILED+=("$label")
    else
      NOT_FOUND+=("$label")
    fi
    return 0
  fi

  for pkg in "${candidates[@]}"; do
    if pkg_installed "$pkg"; then
      log "Already installed ($label): $pkg"
      SKIPPED+=("$pkg")
      return 0
    fi
  done

  for pkg in "${candidates[@]}"; do
    if pacman_has_pkg "$pkg"; then
      log "Installing $label via pacman: $pkg"
      if install_with_pacman "$pkg"; then
        INSTALLED+=("$pkg")
      else
        FAILED+=("$pkg")
      fi
      return 0
    fi
  done

  if [[ -n "$helper" ]]; then
    for pkg in "${candidates[@]}"; do
      if aur_has_pkg "$helper" "$pkg"; then
        log "Installing $label via $helper: $pkg"
        if install_with_aur "$helper" "$pkg"; then
          INSTALLED+=("$pkg")
        else
          FAILED+=("$pkg")
        fi
        return 0
      fi
    done
  fi

  if install_optional_fallback "$label"; then
    log "Installed $label using fallback installer."
    return 0
  fi

  warn "No installable package found for $label (candidates: ${candidates[*]})"
  if (( required == 1 )); then
    FAILED+=("$label")
  else
    NOT_FOUND+=("$label")
  fi
}

install_minimal_profile() {
  local helper="$1"
  install_from_candidates "hyprland" "$helper" 1 hyprland
  install_from_candidates "hypridle" "$helper" 1 hypridle
  install_from_candidates "hyprlock" "$helper" 1 hyprlock
  install_from_candidates "hyprpaper" "$helper" 0 hyprpaper
  install_from_candidates "hyprsunset" "$helper" 0 hyprsunset
  install_from_candidates "xdg-desktop-portal-hyprland" "$helper" 1 xdg-desktop-portal-hyprland
  install_from_candidates "hyprland-preview-share-picker" "$helper" 0 hyprland-preview-share-picker hyprland-preview-share-picker-git
  install_from_candidates "waybar" "$helper" 1 waybar
  install_from_candidates "walker" "$helper" 1 walker walker-bin walker-git
  install_from_candidates "swayosd" "$helper" 0 swayosd
  install_from_candidates "uwsm" "$helper" 0 uwsm
  install_from_candidates "mako" "$helper" 1 mako
}

install_full_profile() {
  local helper="$1"
  install_minimal_profile "$helper"

  install_from_candidates "alacritty" "$helper" 0 alacritty
  install_from_candidates "ghostty" "$helper" 0 ghostty ghostty-bin ghostty-git
  install_from_candidates "kitty" "$helper" 0 kitty
  install_from_candidates "git" "$helper" 1 git
  install_from_candidates "neovim" "$helper" 0 neovim
  install_from_candidates "helix" "$helper" 0 helix
  install_from_candidates "ranger" "$helper" 0 ranger
  install_from_candidates "lazygit" "$helper" 0 lazygit
  install_from_candidates "lazydocker" "$helper" 0 lazydocker
  install_from_candidates "eza" "$helper" 0 eza
  install_from_candidates "btop" "$helper" 0 btop
  install_from_candidates "fastfetch" "$helper" 0 fastfetch
  install_from_candidates "fontconfig" "$helper" 1 fontconfig
  install_from_candidates "nautilus" "$helper" 0 nautilus
  install_from_candidates "libvirt" "$helper" 0 libvirt
  install_from_candidates "virt-manager" "$helper" 0 virt-manager
  install_from_candidates "looking-glass" "$helper" 0 looking-glass
  install_from_candidates "snyk" "$helper" 0 snyk snyk-cli
}

main() {
  local aur_helper=""

  parse_args "$@"
  require_arch

  if ! have_cmd sudo && (( EUID != 0 )); then
    err "'sudo' is required to install pacman packages."
    exit 1
  fi

  if aur_helper="$(get_aur_helper)"; then
    log "Using AUR helper: $aur_helper"
  else
    warn "No AUR helper found (yay/paru). AUR-only packages may fail."
    aur_helper=""
  fi

  log "Profile: $PROFILE"
  (( DRY_RUN == 1 )) && log "Mode: dry-run"

  if [[ "$PROFILE" == "minimal" ]]; then
    install_minimal_profile "$aur_helper"
  else
    install_full_profile "$aur_helper"
  fi

  printf '\n=== Summary ===\n'
  printf 'Installed/Planned: %d\n' "${#INSTALLED[@]}"
  printf 'Already/Skipped:   %d\n' "${#SKIPPED[@]}"
  printf 'Not Found/Skipped: %d\n' "${#NOT_FOUND[@]}"
  printf 'Failed:            %d\n' "${#FAILED[@]}"

  if [[ ${#NOT_FOUND[@]} -gt 0 ]]; then
    printf '\nNot found (skipped):\n'
    printf '  - %s\n' "${NOT_FOUND[@]}"
  fi

  if [[ ${#FAILED[@]} -gt 0 ]]; then
    printf '\nFailed items:\n'
    printf '  - %s\n' "${FAILED[@]}"
    exit 1
  fi
}

main "$@"
