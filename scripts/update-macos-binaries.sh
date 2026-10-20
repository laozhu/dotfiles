#!/usr/bin/env bash
# Pin official Apple Silicon release assets to the versions in flake.lock.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
destination="$repo_dir/macos-binaries.json"
versions="$(DOTFILES_BINARY_FLAKE="path:$repo_dir" nix eval --json --impure --expr '
  let
    flake = builtins.getFlake (builtins.getEnv "DOTFILES_BINARY_FLAKE");
    pkgs = flake.inputs.nixpkgs.legacyPackages.aarch64-darwin;
    agents = flake.inputs.llm-agents.packages.aarch64-darwin;
    atLeast = minimum: version:
      if pkgs.lib.versionOlder version minimum then minimum else version;
  in {
    pnpm = atLeast "12.9.1" pkgs.pnpm.version;
    uv = atLeast "0.12.23" pkgs.uv.version;
    sing-box = atLeast "1.14.2" pkgs.sing-box.version;
    bws = pkgs.bws.version;
    herdr = agents.herdr.version;
    kimi-code = agents.kimi-code.version;
    pi = agents.pi.version;
  }
')"

result='{}'
for name in pnpm uv sing-box bws herdr kimi-code pi; do
  version="$(jq -er --arg name "$name" '.[$name]' <<<"$versions")"
  case "$name" in
    pnpm) repo=pnpm/pnpm; tag="v$version"; asset=pnpm-darwin-arm64.tar.gz ;;
    uv) repo=astral-sh/uv; tag="$version"; asset=uv-aarch64-apple-darwin.tar.gz ;;
    sing-box) repo=SagerNet/sing-box; tag="v$version"; asset="sing-box-$version-darwin-arm64.tar.gz" ;;
    bws) repo=bitwarden/sdk-sm; tag="bws-v$version"; asset="bws-aarch64-apple-darwin-$version.zip" ;;
    herdr) repo=herdrdev/herdr; tag="v$version"; asset=herdr-macos-aarch64 ;;
    kimi-code) repo=MoonshotAI/kimi-code; tag="@moonshot-ai/kimi-code@$version"; asset=kimi-code-darwin-arm64.tar.gz ;;
    pi) repo=earendil-works/pi; tag="v$version"; asset=pi-darwin-arm64.tar.gz ;;
  esac
  printf 'Pinning %s %s (official macOS binary)...\n' "$name" "$version" >&2
  encoded_tag="$(jq -rn --arg tag "$tag" '$tag | @uri')"
  release="$(gh api "repos/$repo/releases/tags/$encoded_tag")"
  pin="$(jq -e --arg asset "$asset" --arg version "$version" --arg repo "$repo" '
    if .draft or .prerelease then error("expected a stable release") else . end |
    [.assets[] | select(.name == $asset)] |
    if length != 1 then error("missing or ambiguous macOS release asset") else .[0] end |
    if (.digest // "" | test("^sha256:[0-9a-f]{64}$")) and
       (.browser_download_url | startswith("https://github.com/" + $repo + "/releases/download/"))
    then {version: $version, url: .browser_download_url, sha256: (.digest | ltrimstr("sha256:"))}
    else error("release asset has no valid SHA-256 or official URL") end
  ' <<<"$release")"
  result="$(jq --arg name "$name" --argjson pin "$pin" '. + {($name): $pin}' <<<"$result")"
done

# Write only after every release has been validated; a failed update keeps old pins.
temporary="$(mktemp "$repo_dir/.macos-binaries.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
jq -S . <<<"$result" >"$temporary"
chmod 0644 "$temporary"
mv -f "$temporary" "$destination"
trap - EXIT
