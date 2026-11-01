#!/usr/bin/env bash
# Source before Nix commands; retain caller settings and avoid changing daemon config.
# Once installed in Determinate's system config, do not resend restricted keys
# as client overrides. Keep the fallback for bootstrap and CI.
if command -v nix >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 &&
  env -u NIX_CONFIG nix config show --json 2>/dev/null | jq -e '
    (.substituters.value | any(. == "https://cache.thalheim.io" or . == "https://cache.thalheim.io/")) and
    (."trusted-public-keys".value | index("cache.thalheim.io-1:R7msbosLEZKrxk/lKxf9BTjOOH7Ax3H0Qj0/6wiHOgc=") != null)
  ' >/dev/null; then
  return 0
fi
dotfiles_cache_config="$(cat "$(dirname "${BASH_SOURCE[0]}")/../nix-caches.conf")"
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG$'\n'}$dotfiles_cache_config"
unset dotfiles_cache_config
