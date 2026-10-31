#!/usr/bin/env bash
# Source this file; profile selection is local to the current user, never inferred.
dotfiles_profile() {
  local requested="${1:-}" saved='' file="$HOME/.config/dotfiles/profile"
  if [ -f "$file" ]; then
    saved="$(cat "$file")"
    case "$saved" in
      home | work) ;;
      *)
        printf 'Invalid profile in %s; expected home or work.\n' "$file" >&2
        return 2
        ;;
    esac
  fi
  case "$requested" in
    '' | home | work) ;;
    *)
      printf 'Profile must be home or work.\n' >&2
      return 2
      ;;
  esac
  if [ -n "$requested" ] && [ -n "$saved" ] && [ "$requested" != "$saved" ]; then
    printf 'Profile is already %s. Refusing to switch to %s because Homebrew cleanup may remove apps and data.\n' "$saved" "$requested" >&2
    return 2
  fi
  if [ -z "$saved" ]; then
    if [ -z "$requested" ]; then
      printf 'No machine profile. Run ./bootstrap.sh --profile home (or work).\n' >&2
      return 2
    fi
    mkdir -p "$(dirname "$file")" || return
    printf '%s\n' "$requested" >"$file" || return
    saved="$requested"
  fi
  printf '%s\n' "$saved"
}
