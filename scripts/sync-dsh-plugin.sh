#!/usr/bin/env bash
set -euo pipefail

profile="$1"
package="$2"
version="$3"
profile_dir="${DSH_HOME:-$HOME/.dsh}/profiles/$profile"
manifest="$profile_dir/package.json"
installed="$profile_dir/node_modules/$package/package.json"

# Check the actual package and bundle registration, not just an install marker.
if [ -f "$manifest" ] && [ -f "$installed" ] &&
  jq -e --arg p "$package" --arg v "$version" \
    '.dependencies[$p] == $v and (.dsh.profile.bundles | index($p) != null)' "$manifest" >/dev/null &&
  jq -e --arg p "$package" --arg v "$version" \
    '.name == $p and .version == $v' "$installed" >/dev/null; then
  echo "==> DSH profile $profile: $package@$version already installed."
  exit 0
fi

# The official profile installer preserves local patches and the credential store.
echo "==> DSH profile $profile: installing $package@$version"
dsh plugin --profile "$profile" add "$package@$version"
