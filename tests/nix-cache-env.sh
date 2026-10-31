#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# Keep caller settings, while enabling the project's signed upstream cache.
export NIX_CONFIG='max-jobs = 3'
source "$repo_dir/scripts/nix-cache-env.sh"
case "$NIX_CONFIG" in
  'max-jobs = 3'*) ;;
  *)
    echo 'cache setup discarded caller NIX_CONFIG' >&2
    exit 1
    ;;
esac
nix config show --json | jq -e '
  (.substituters.value | index("https://cache.nixos.org/") != null or index("https://cache.nixos.org") != null) and
  (.substituters.value | index("https://cache.thalheim.io") != null or index("https://cache.thalheim.io/") != null) and
  (."trusted-public-keys".value | index("cache.thalheim.io-1:R7msbosLEZKrxk/lKxf9BTjOOH7Ax3H0Qj0/6wiHOgc=") != null) and
  ."require-sigs".value == true and
  (."max-jobs".value | tostring) == "3"
' >/dev/null
