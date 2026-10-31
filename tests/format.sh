#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
git -C "$fixture" init -q
cp "$repo_dir/format.sh" "$repo_dir/flake.nix" "$repo_dir/flake.lock" "$fixture/"
git -C "$fixture" add flake.nix flake.lock

printf 'echo    hello\n' >"$fixture/example.sh"
printf '{"a":1}\n' >"$fixture/example.json"
printf 'a:    1\n' >"$fixture/example.yaml"
printf 'a=1\n' >"$fixture/example.toml"
printf '#    Heading\n' >"$fixture/example.md"
printf '{a=1;}\n' >"$fixture/example.nix"
printf 'const a:number=1\n' >"$fixture/example.ts"
printf 'const a={b:1}\n' >"$fixture/example.js"
printf 'local a={b=1}\n' >"$fixture/example.lua"
mkdir -p "$fixture/secrets" "$fixture/ignored"
printf '{"generated":true}\n' >"$fixture/macos-binaries.json"
printf 'private:    leave-alone\n' >"$fixture/secrets/example.yaml"
printf '#    Generated\n' >"$fixture/CHANGELOG.md"
printf '{"ignored":true}\n' >"$fixture/ignored/config.json"
printf 'ignored/\n' >"$fixture/.gitignore"
ln -s example.json "$fixture/link.json"

# A failing check must leave all inputs untouched.
cp -R "$fixture" "$fixture.before"
trap 'rm -rf "$fixture" "$fixture.before"' EXIT
if bash "$fixture/format.sh" --check >"$fixture/check.log" 2>&1; then
  echo 'format check accepted unformatted files' >&2
  exit 1
fi
diff -r --exclude=.git --exclude=check.log "$fixture.before" "$fixture"

if ! bash "$fixture/format.sh" >"$fixture/write.log" 2>&1; then
  cat "$fixture/write.log" >&2
  exit 1
fi
if ! bash "$fixture/format.sh" --check >"$fixture/check.log" 2>&1; then
  cat "$fixture/check.log" >&2
  exit 1
fi
for extension in sh json yaml toml md nix ts js lua; do
  if cmp -s "$fixture.before/example.$extension" "$fixture/example.$extension"; then
    echo "formatter missed $extension" >&2
    exit 1
  fi
done
for file in macos-binaries.json secrets/example.yaml CHANGELOG.md ignored/config.json; do
  cmp "$fixture.before/$file" "$fixture/$file"
done
test -L "$fixture/link.json"

# A newly added TypeScript file must be checked even before git add.
printf 'const extra:number=2\n' >"$fixture/new.ts"
if bash "$fixture/format.sh" --check >"$fixture/check.log" 2>&1; then
  echo 'format check missed an untracked TypeScript file' >&2
  exit 1
fi
test "$(cat "$fixture/new.ts")" = 'const extra:number=2'
