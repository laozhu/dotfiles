#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
publisher="$repo_dir/scripts/publish-sing-box-config.sh"
coreutils_bin="$(
  nix eval --raw "$repo_dir#darwinConfigurations.mac.pkgs.coreutils"
)/bin"
jq_bin="$(command -v jq)"
sing_box_bin="$(command -v sing-box)"

bash -n "$publisher"
test -x "$jq_bin"
test -x "$sing_box_bin"

publish_test_root="$(mktemp -d)"
cleanup_publish_tests() {
  rm -rf "$publish_test_root"
}
trap cleanup_publish_tests EXIT

assert_no_publish_temps() {
  if find "$publish_test_root" \
    -name '.config.json.*' \
    -print -quit \
    | grep -q .; then
    echo "publish helper left a temporary file behind" >&2
    exit 1
  fi
}

run_publisher() {
  bash \
    "$publisher" \
    "$1" \
    "$2" \
    "$3" \
    "$coreutils_bin" \
    "$jq_bin" \
    "$sing_box_bin"
}

valid_candidate="$publish_test_root/valid-candidate.json"
replacement_candidate="$publish_test_root/replacement-candidate.json"
printf '%s' '{}' >"$valid_candidate"
printf '%s' \
  '{"outbounds":[{"type":"direct","tag":"direct"}]}' \
  >"$replacement_candidate"

first_state="$publish_test_root/first/state"
first_final="$first_state/config.json"
run_publisher "$first_state" "$first_final" "$valid_candidate"
cmp -s "$valid_candidate" "$first_final"
test "$("$coreutils_bin/stat" -c '%a' "$first_state")" = '700'
test "$("$coreutils_bin/stat" -c '%a' "$first_final")" = '600'
assert_no_publish_temps

printf '%s' 'old regular config' >"$first_final"
run_publisher "$first_state" "$first_final" "$replacement_candidate"
cmp -s "$replacement_candidate" "$first_final"
test "$("$coreutils_bin/stat" -c '%a' "$first_final")" = '600'
assert_no_publish_temps

missing_state="$publish_test_root/missing-candidate"
"$coreutils_bin/install" -d "$missing_state"
printf '%s' 'missing candidate sentinel' >"$missing_state/config.json"
if run_publisher \
  "$missing_state" \
  "$missing_state/config.json" \
  "$publish_test_root/does-not-exist.json" \
  2>/dev/null; then
  echo "publish helper accepted a missing candidate" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$missing_state/config.json")" = \
  'missing candidate sentinel'
assert_no_publish_temps

unreadable_state="$publish_test_root/unreadable-candidate"
unreadable_candidate="$publish_test_root/unreadable-candidate.json"
"$coreutils_bin/install" -d "$unreadable_state"
printf '%s' 'unreadable candidate sentinel' \
  >"$unreadable_state/config.json"
printf '%s' '{}' >"$unreadable_candidate"
"$coreutils_bin/chmod" 000 "$unreadable_candidate"
if run_publisher \
  "$unreadable_state" \
  "$unreadable_state/config.json" \
  "$unreadable_candidate" \
  2>/dev/null; then
  echo "publish helper accepted an unreadable candidate" >&2
  exit 1
fi
"$coreutils_bin/chmod" 0600 "$unreadable_candidate"
test "$("$coreutils_bin/cat" "$unreadable_state/config.json")" = \
  'unreadable candidate sentinel'
assert_no_publish_temps

invalid_json_state="$publish_test_root/invalid-json"
invalid_json_candidate="$publish_test_root/invalid-json-candidate.json"
"$coreutils_bin/install" -d "$invalid_json_state"
printf '%s' 'invalid JSON sentinel' \
  >"$invalid_json_state/config.json"
printf '%s' 'not JSON' >"$invalid_json_candidate"
if run_publisher \
  "$invalid_json_state" \
  "$invalid_json_state/config.json" \
  "$invalid_json_candidate" \
  >/dev/null 2>&1; then
  echo "publish helper accepted invalid JSON" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$invalid_json_state/config.json")" = \
  'invalid JSON sentinel'
assert_no_publish_temps

invalid_sing_box_state="$publish_test_root/invalid-sing-box"
invalid_sing_box_candidate="$publish_test_root/invalid-sing-box-candidate.json"
"$coreutils_bin/install" -d "$invalid_sing_box_state"
printf '%s' 'invalid sing-box sentinel' \
  >"$invalid_sing_box_state/config.json"
printf '%s' \
  '{"outbounds":[{"type":"not-a-type","tag":"invalid"}]}' \
  >"$invalid_sing_box_candidate"
if run_publisher \
  "$invalid_sing_box_state" \
  "$invalid_sing_box_state/config.json" \
  "$invalid_sing_box_candidate" \
  >/dev/null 2>&1; then
  echo "publish helper accepted invalid sing-box semantics" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$invalid_sing_box_state/config.json")" = \
  'invalid sing-box sentinel'
assert_no_publish_temps

state_target="$publish_test_root/state-target"
state_link="$publish_test_root/state-link"
"$coreutils_bin/install" -d -m 0755 "$state_target"
printf '%s' 'state target sentinel' >"$state_target/sentinel"
ln -s "$state_target" "$state_link"
if run_publisher \
  "$state_link" \
  "$state_link/config.json" \
  "$valid_candidate" \
  2>/dev/null; then
  echo "publish helper accepted a symlink state directory" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$state_target/sentinel")" = \
  'state target sentinel'
test "$("$coreutils_bin/stat" -c '%a' "$state_target")" = '755'
test ! -e "$state_target/config.json"
assert_no_publish_temps

state_file="$publish_test_root/state-file"
printf '%s' 'state file sentinel' >"$state_file"
if run_publisher \
  "$state_file" \
  "$state_file/config.json" \
  "$valid_candidate" \
  2>/dev/null; then
  echo "publish helper accepted a non-directory state path" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$state_file")" = 'state file sentinel'
assert_no_publish_temps

unexpected_state="$publish_test_root/unexpected"
if run_publisher \
  "$unexpected_state" \
  "$unexpected_state/other.json" \
  "$valid_candidate" \
  2>/dev/null; then
  echo "publish helper accepted an unexpected final path" >&2
  exit 1
fi
test ! -e "$unexpected_state"
assert_no_publish_temps

directory_state="$publish_test_root/final-directory"
"$coreutils_bin/install" -d "$directory_state/config.json"
printf '%s' 'directory sentinel' \
  >"$directory_state/config.json/sentinel"
if run_publisher \
  "$directory_state" \
  "$directory_state/config.json" \
  "$valid_candidate" \
  2>/dev/null; then
  echo "publish helper replaced a final directory" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$directory_state/config.json/sentinel")" = \
  'directory sentinel'
assert_no_publish_temps

symlink_state="$publish_test_root/final-symlink"
symlink_target="$publish_test_root/final-symlink-target"
"$coreutils_bin/install" -d "$symlink_state"
printf '%s' 'final symlink sentinel' >"$symlink_target"
ln -s "$symlink_target" "$symlink_state/config.json"
if run_publisher \
  "$symlink_state" \
  "$symlink_state/config.json" \
  "$valid_candidate" \
  2>/dev/null; then
  echo "publish helper replaced a final symlink" >&2
  exit 1
fi
test -L "$symlink_state/config.json"
test "$("$coreutils_bin/cat" "$symlink_target")" = \
  'final symlink sentinel'
assert_no_publish_temps

instrumented_bin="$publish_test_root/instrumented-coreutils"
"$coreutils_bin/install" -d "$instrumented_bin"
for utility in install mktemp rm cat chmod; do
  ln -s "$coreutils_bin/$utility" "$instrumented_bin/$utility"
done

cat >"$instrumented_bin/mv" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$3" >"$MV_PATH_LOG"
exec "$REAL_MV" "$@"
SH
cat >"$publish_test_root/jq-validator" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$3" >"$JQ_PATH_LOG"
exec "$REAL_JQ" "$@"
SH
cat >"$publish_test_root/sing-box-validator" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$3" >"$SING_BOX_PATH_LOG"
exec "$REAL_SING_BOX" "$@"
SH
"$coreutils_bin/chmod" 0755 \
  "$instrumented_bin/mv" \
  "$publish_test_root/jq-validator" \
  "$publish_test_root/sing-box-validator"

instrumented_state="$publish_test_root/instrumented-state"
instrumented_final="$instrumented_state/config.json"
export MV_PATH_LOG="$publish_test_root/mv-path.log"
export JQ_PATH_LOG="$publish_test_root/jq-path.log"
export SING_BOX_PATH_LOG="$publish_test_root/sing-box-path.log"
export REAL_MV="$coreutils_bin/mv"
export REAL_JQ="$jq_bin"
export REAL_SING_BOX="$sing_box_bin"
bash \
  "$publisher" \
  "$instrumented_state" \
  "$instrumented_final" \
  "$valid_candidate" \
  "$instrumented_bin" \
  "$publish_test_root/jq-validator" \
  "$publish_test_root/sing-box-validator"
jq_validated_path="$("$coreutils_bin/cat" "$JQ_PATH_LOG")"
sing_box_validated_path="$("$coreutils_bin/cat" "$SING_BOX_PATH_LOG")"
mv_source_path="$("$coreutils_bin/cat" "$MV_PATH_LOG")"
test "$jq_validated_path" = "$sing_box_validated_path"
test "$jq_validated_path" = "$mv_source_path"
case "$mv_source_path" in
  "$instrumented_state"/.config.json.*) ;;
  *)
    echo "validators and mv did not receive the publication temp" >&2
    exit 1
    ;;
esac
cmp -s "$valid_candidate" "$instrumented_final"
assert_no_publish_temps

post_activation="$(
  nix eval --raw \
    "$repo_dir#darwinConfigurations.mac.config.system.activationScripts.postActivation.text"
)"
secrets_line="$(
  printf '%s\n' "$post_activation" \
    | grep -n -m1 'Setting up secrets' \
    | cut -d: -f1
)"
validation_line="$(
  printf '%s\n' "$post_activation" \
    | grep -n -m1 'validating sing-box configuration' \
    | cut -d: -f1
)"
test "$secrets_line" -lt "$validation_line"

before_downgrade="${post_activation%%/usr/bin/sudo -u *}"
if printf '%s\n' "$before_downgrade" \
  | grep -Eq '/bin/(install|chown|chmod|mktemp|mv|cat|jq|sing-box)([[:space:]]|$)'; then
  echo "root activation reads the candidate or mutates the user home" >&2
  exit 1
fi
publication_block="${post_activation#*validating sing-box configuration}"
if printf '%s\n' "$publication_block" | grep -Fq '|'; then
  echo "activation pipes candidate content across the user boundary" >&2
  exit 1
fi
printf '%s\n' "$post_activation" \
  | grep -F '/usr/bin/sudo -u rich --' >/dev/null
printf '%s\n' "$post_activation" \
  | grep -F -- '-publish-sing-box-config.sh' >/dev/null

trap - EXIT
cleanup_publish_tests

