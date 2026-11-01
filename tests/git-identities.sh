#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
fixture="$(cd "$fixture" && pwd -P)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"
export XDG_CONFIG_HOME="$HOME/.config"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
unset GH_CONFIG_DIR GIT_SSH_COMMAND DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES
mkdir -p "$HOME/.config/git" "$HOME/.config/direnv" "$HOME/Developer" "$HOME/.ssh"
for key in id_ed25519 id_ed25519_laozhu; do
  ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/$key"
done
cp "$repo_dir/home/.gitconfig" "$HOME/.gitconfig"
cp "$repo_dir/home/.config/git/laozhu.inc" "$HOME/.config/git/laozhu.inc"
cp "$repo_dir/home/.config/direnv/direnvrc" "$HOME/.config/direnv/direnvrc"
for owner in laozhu beebat-dev; do
  mkdir -p "$HOME/Developer/$owner"
  cp "$repo_dir/home/.config/direnv/github.envrc" "$HOME/Developer/$owner/.envrc"
  direnv allow "$HOME/Developer/$owner/.envrc"
done

for owner in laozhu beebat-dev ritchie-paid laozhu-other beebat-dev-other; do
  directory="$HOME/Developer/$owner/nested/repo"
  mkdir -p "$directory"
  git -C "$directory" init -q
  case "$owner" in
    laozhu | beebat-dev)
      email=laozhu.me@gmail.com
      key=id_ed25519_laozhu
      gh_config=gh-laozhu
      ;;
    *)
      email=204663844+ritchie-paid@users.noreply.github.com
      key=id_ed25519
      gh_config=gh
      ;;
  esac
  test "$(git -C "$directory" config user.email)" = "$email"
  test "$(git -C "$directory" config user.name)" = 'Ritchie Zhu'
  test "$(git -C "$directory" config core.sshCommand)" = "ssh -i ~/.ssh/$key -o IdentitiesOnly=yes"
  test "$(git -C "$directory" config gpg.format)" = ssh
  test "$(git -C "$directory" config --bool commit.gpgsign)" = true
  test "$(git -C "$directory" config user.signingkey)" = "~/.ssh/$key"
  git -C "$directory" commit --allow-empty -qm 'Verify automatic SSH signing'
  printf '%s namespaces="git" %s\n' "$email" "$(cat "$HOME/.ssh/$key.pub")" >"$fixture/allowed_signers"
  git -C "$directory" -c gpg.ssh.allowedSignersFile="$fixture/allowed_signers" verify-commit HEAD
  helper="$(git -C "$directory" config --get-all credential.https://github.com.helper | tail -1)"
  [[ "$helper" == *"$gh_config"* ]]
done

# Real clone setup must select the destination's key before contacting SSH.
mkdir -p "$fixture/bin"
cat >"$fixture/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_IDENTITY_TEST_LOG"
exit 1
SSH
chmod +x "$fixture/bin/ssh"
export GIT_IDENTITY_TEST_LOG="$fixture/ssh.log"
for owner in laozhu beebat-dev ritchie-paid; do
  : >"$GIT_IDENTITY_TEST_LOG"
  if PATH="$fixture/bin:$PATH" git clone git@github.com:example/repo.git \
    "$HOME/Developer/$owner/cloned" >/dev/null 2>&1; then
    echo 'Mock SSH unexpectedly completed a clone' >&2
    exit 1
  fi
  case "$owner" in
    laozhu | beebat-dev) key=id_ed25519_laozhu ;;
    *) key=id_ed25519 ;;
  esac
  grep -Fq -- "-i $HOME/.ssh/$key -o IdentitiesOnly=yes" "$GIT_IDENTITY_TEST_LOG"
done

# Both a parent .envrc and an independently approved child .envrc select laozhu.
for owner in laozhu beebat-dev; do
  directory="$HOME/Developer/$owner/nested/repo"
  (
    cd "$directory"
    eval "$(direnv export bash)"
    test "$GH_CONFIG_DIR" = "$HOME/.config/gh-laozhu"
    test -z "${GIT_SSH_COMMAND+x}"
    cd "$HOME"
    eval "$(direnv export bash)"
    test -z "${GH_CONFIG_DIR+x}"
    test -z "${GIT_SSH_COMMAND+x}"
  )
  printf 'export PROJECT_FLAG=1\n' >"$directory/.envrc"
  direnv allow "$directory/.envrc"
  (cd "$directory"; direnv exec . bash -c '
    test "$GH_CONFIG_DIR" = "$HOME/.config/gh-laozhu"
    test "$PROJECT_FLAG" = 1
    test -z "${GIT_SSH_COMMAND+x}"
  ')
done
printf '%s\n' 'Git and GitHub CLI directory identity tests passed.'
