#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  printf 'Usage: %s [--update|-u]\n' "${0##*/}" >&2
}

update_inputs=false
case "$#" in
  0)
    ;;
  1)
    case "$1" in
      -u | --update)
        update_inputs=true
        ;;
      *)
        usage
        exit 2
        ;;
    esac
    ;;
  *)
    usage
    exit 2
    ;;
esac

"$DIR/scripts/check-sops-age-key.sh"
"$DIR/scripts/check-sing-box-config.sh"

if [ "$update_inputs" = true ]; then
  nix flake update --flake "$DIR"
fi

exec sudo darwin-rebuild switch --flake "$DIR#mac"
