#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
node --check "$repo_dir/scripts/render-sing-box-config.mjs"

node --input-type=module - "$repo_dir/scripts/render-sing-box-config.mjs" <<'NODE'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const rendererPath = process.argv[2];
const { renderConfig } = await import(pathToFileURL(rendererPath));

assert.equal(
  renderConfig(
    '{"secret":"__SOPS_TEST__"}',
    { __SOPS_TEST__: "root/value" },
    { root: { value: "rendered" } },
  ),
  '{"secret":"rendered"}',
);
assert.throws(
  () => renderConfig(
    '{"secret":"__SOPS_TEST__"}',
    { __SOPS_TEST__: "root/missing" },
    { root: {} },
  ),
  /missing SOPS key path: root\/missing/,
);
assert.throws(
  () => renderConfig(
    '{"secret":"__SOPS_TEST__"}',
    { __SOPS_TEST__: "root/value" },
    { root: { value: "" } },
  ),
  /invalid secret value for: root\/value/,
);
assert.equal(
  renderConfig(
    '{"a":"__SOPS_TEST__","b":"__SOPS_TEST__"}',
    { __SOPS_TEST__: "root/value" },
    { root: { value: "rendered" } },
  ),
  '{"a":"rendered","b":"rendered"}',
);
assert.throws(
  () => renderConfig(
    '{"secret":"unchanged"}',
    { __SOPS_TEST__: "root/value" },
    { root: { value: "rendered" } },
  ),
  /expected marker at least once: __SOPS_TEST__/,
);
assert.throws(
  () => renderConfig(
    '{"secret":"__SOPS_UNKNOWN__"}',
    {},
    {},
  ),
  /unresolved SOPS marker remains/,
);
assert.throws(
  () => renderConfig(
    '{"secret":"__SOPS_TEST__"}',
    { __SOPS_TEST__: "root/value" },
    { root: { value: '"' } },
  ),
  SyntaxError,
);
NODE

nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.sops.templates.sing-box-candidate.path" \
  | grep -Fx '/run/secrets/rendered/sing-box-candidate.json'

nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.sops.age.keyFile" \
  | grep -Fx '/Users/rich/Library/Application Support/sops/age/keys.txt'

nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.sops.templates.sing-box-candidate.owner" \
  | grep -Fx 'rich'

nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.sops.templates.sing-box-candidate.group" \
  | grep -Fx 'staff'

nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.sops.templates.sing-box-candidate.mode" \
  | grep -Fx '0400'

