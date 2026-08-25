#!/usr/bin/env bash
set -euo pipefail

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

tests=(
  check-sops-age-key.sh
  bootstrap.sh
  prefetch-uu-booster.sh
  rebuild.sh
  repository-policy.sh
  pi-config.sh
  sing-box-config.sh
  render-sing-box-config.sh
  publish-sing-box-config.sh
)

for test_name in "${tests[@]}"; do
  printf '==> %s\n' "$test_name"
  bash "$tests_dir/$test_name"
done

printf '%s\n' 'All tests passed.'
