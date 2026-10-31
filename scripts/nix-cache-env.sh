#!/usr/bin/env bash
# Source before Nix commands; retain caller settings and avoid changing daemon config.
dotfiles_cache_config="$(cat "$(dirname "${BASH_SOURCE[0]}")/../nix-caches.conf")"
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG$'\n'}$dotfiles_cache_config"
unset dotfiles_cache_config
