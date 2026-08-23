#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
uu_test_root="$(mktemp -d)"
cleanup_uu_tests() {
  rm -rf "$uu_test_root"
}
trap cleanup_uu_tests EXIT

uu_prefetch="$repo_dir/scripts/prefetch-uu-booster.sh"
uu_test_bin="$uu_test_root/bin"
uu_test_cache_root="$uu_test_root/cache"
uu_test_cache="$uu_test_cache_root/downloads/cf06028bd51147d9ef0f42c622fd0dd7bea21924443c072454e4bdc37b3ba804--UU-macOS-2.8.14.dmg"
uu_test_dmg="$uu_test_root/signed.dmg"
uu_test_cask="$uu_test_root/uu-booster.rb"
uu_test_curl_log="$uu_test_root/curl.log"
mkdir -p "$uu_test_bin" "$uu_test_cache_root"
printf 'signed dmg fixture\n' >"$uu_test_dmg"
cat >"$uu_test_cask" <<'RUBY'
cask "uu-booster" do
  version "2.8.14"
  sha256 "eb030da6c6c30b0fc16952274fe661c5b4651f0371061379773cd6ca848bee3b"
  url "https://uu.gdl.netease.com/UU-macOS-#{version}.dmg"
end
RUBY

cat >"$uu_test_bin/brew" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "--cache")
    printf '%s\n' "$UU_TEST_CACHE_ROOT"
    ;;
  *)
    exit 64
    ;;
esac
SH
cat >"$uu_test_bin/curl" <<'SH'
#!/usr/bin/env bash
output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
printf '%s\n' "$url" >>"$UU_TEST_CURL_LOG"
signed_url="${UU_TEST_SIGNED_URL:-https://uu.gdl.netease.com/UU-macOS-2.8.14.dmg?type=pc&key1=test-signature&key2=test-key}"
case "$url" in
  "https://adl.netease.com/d/g/uu/c/uumac?type=pc")
    printf 'var pc_link = "%s";\n' "$signed_url"
    ;;
  *)
    if [ "$url" = "$signed_url" ]; then
      cp "$UU_TEST_DMG" "$output"
    else
      exit 65
    fi
    ;;
esac
SH
chmod 0755 "$uu_test_bin/brew" "$uu_test_bin/curl"

export UU_TEST_CACHE_ROOT="$uu_test_cache_root"
export UU_TEST_CURL_LOG="$uu_test_curl_log"
export UU_TEST_DMG="$uu_test_dmg"
PATH="$uu_test_bin:/usr/bin:/bin" \
  bash "$uu_prefetch" "$uu_test_cask" >/dev/null
if ! cmp -s "$uu_test_dmg" "$uu_test_cache"; then
  echo "UU Booster prefetch did not populate Homebrew's verified cache" >&2
  exit 1
fi

: >"$uu_test_curl_log"
PATH="$uu_test_bin:/usr/bin:/bin" \
  bash "$uu_prefetch" "$uu_test_cask" >/dev/null
if [ -s "$uu_test_curl_log" ]; then
  echo "UU Booster prefetch accessed the network for a valid cache entry" >&2
  exit 1
fi

rm -f "$uu_test_cache"
foreign_output="$uu_test_root/foreign-output"
if UU_TEST_SIGNED_URL='https://downloads.example.test/UU-macOS-2.8.14.dmg?type=pc&key1=test&key2=test' \
  PATH="$uu_test_bin:/usr/bin:/bin" \
  bash "$uu_prefetch" "$uu_test_cask" >"$foreign_output" 2>&1; then
  echo "UU Booster prefetch accepted a non-NetEase download URL" >&2
  exit 1
fi
if [ -e "$uu_test_cache" ]; then
  echo "UU Booster prefetch cached a download from an untrusted host" >&2
  exit 1
fi

version_output="$uu_test_root/version-output"
if UU_TEST_SIGNED_URL='https://uu.gdl.netease.com/UU-macOS-9.9.9.dmg?type=pc&key1=test&key2=test' \
  PATH="$uu_test_bin:/usr/bin:/bin" \
  bash "$uu_prefetch" "$uu_test_cask" >"$version_output" 2>&1; then
  echo "UU Booster prefetch accepted a mismatched download version" >&2
  exit 1
fi

previous_cache="$uu_test_root/previous-cache"
bad_dmg="$uu_test_root/bad.dmg"
printf 'previous cache\n' >"$previous_cache"
printf 'bad download\n' >"$bad_dmg"
mkdir -p "$(dirname "$uu_test_cache")"
cp "$previous_cache" "$uu_test_cache"
checksum_output="$uu_test_root/checksum-output"
if UU_TEST_DMG="$bad_dmg" \
  PATH="$uu_test_bin:/usr/bin:/bin" \
  bash "$uu_prefetch" "$uu_test_cask" >"$checksum_output" 2>&1; then
  echo "UU Booster prefetch accepted a mismatched SHA-256" >&2
  exit 1
fi
if ! cmp -s "$previous_cache" "$uu_test_cache"; then
  echo "UU Booster prefetch overwrote the previous cache before verification" >&2
  exit 1
fi
if find "$(dirname "$uu_test_cache")" -name '*.incomplete.*' -print -quit |
  grep -q .; then
  echo "UU Booster prefetch left an incomplete download behind" >&2
  exit 1
fi

trap - EXIT
cleanup_uu_tests

