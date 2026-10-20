#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts" "$fixture/bin"
cp "$repo_dir/scripts/update-macos-binaries.sh" "$fixture/scripts/"
cp "$repo_dir/macos-binaries.json" "$fixture/expected.json"
export BINARY_TEST_FIXTURE="$fixture"
cat >"$fixture/bin/nix" <<'SH'
#!/usr/bin/env bash
jq 'map_values(.version)' "$BINARY_TEST_FIXTURE/expected.json"
SH
cat >"$fixture/bin/gh" <<'SH'
#!/usr/bin/env bash
if [ "${BINARY_TEST_API_FAILURE:-0}" = 1 ] && [[ "$2" == *SagerNet* ]]; then exit 29; fi
jq --arg endpoint "$2" --arg missing "${BINARY_TEST_MISSING_ASSET:-0}" \
   --arg bad_hash "${BINARY_TEST_BAD_HASH:-0}" '
  to_entries | map(select(.value.url | contains("/" + ($endpoint | split("/")[1:3] | join("/")) + "/"))) | .[0].value |
  {draft: false, prerelease: false, assets: (if $missing == "1" then [] else [{
    name: (.url | split("/") | last), browser_download_url: .url,
    digest: (if $bad_hash == "1" then null else "sha256:" + .sha256 end)
  }] end)}
' "$BINARY_TEST_FIXTURE/expected.json"
SH
chmod +x "$fixture/bin/nix" "$fixture/bin/gh"
export PATH="$fixture/bin:$PATH"
bash "$fixture/scripts/update-macos-binaries.sh" >/dev/null
cmp "$fixture/expected.json" "$fixture/macos-binaries.json"
for failure in BINARY_TEST_API_FAILURE BINARY_TEST_MISSING_ASSET BINARY_TEST_BAD_HASH; do
  if env "$failure=1" bash "$fixture/scripts/update-macos-binaries.sh" >/dev/null 2>&1; then
    echo "Binary update accepted $failure" >&2
    exit 1
  fi
  cmp "$fixture/expected.json" "$fixture/macos-binaries.json"
done
