#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
fixture="$(cd "$fixture" && pwd -P)"
trap 'rm -rf "$fixture"' EXIT

# Evaluate with the real HOME before setting up isolated account fixtures.
for profile in home work; do
  nix eval --json "$repo_dir#darwinConfigurations.$profile.config.home-manager.users.rich" \
    --apply 'c: { git = c.home.file.".gitconfig".text; direnv = c.home.file.".config/direnv/direnvrc".text; zsh = c.programs.zsh.initContent; fragments = builtins.filter (p: builtins.match ".config/git/.*[.]inc" p != null && c.home.file.${p}.enable) (builtins.attrNames c.home.file); }' \
    >"$fixture/$profile.json"
  jq -er '.git | select(type == "string" and length > 0)' "$fixture/$profile.json" >"$fixture/$profile.gitconfig"
  jq -er '.direnv | select(type == "string" and length > 0)' "$fixture/$profile.json" >"$fixture/$profile.direnvrc"
  jq -r '.zsh' "$fixture/$profile.json" >"$fixture/$profile.zshrc"
done

export GIT_CONFIG_NOSYSTEM=1
unset GH_CONFIG_DIR GITHUB_ACTOR GH_TOKEN GITHUB_TOKEN GIT_SSH_COMMAND DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES
mkdir -p "$fixture/bin"
cat >"$fixture/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_IDENTITY_TEST_LOG"
exit 1
SSH
chmod +x "$fixture/bin/ssh"
export GIT_IDENTITY_TEST_LOG="$fixture/ssh.log"

for profile in home work; do
  export HOME="$fixture/$profile"
  export XDG_CONFIG_HOME="$HOME/.config"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  mkdir -p "$HOME/.config/git" "$HOME/.config/direnv" "$HOME/Developer" "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519_laozhu"
  if [ "$profile" = work ]; then
    ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
  fi
  cp "$fixture/$profile.gitconfig" "$HOME/.gitconfig"
  while IFS= read -r fragment; do
    cp "$repo_dir/home/$fragment" "$HOME/$fragment"
  done < <(jq -r '.fragments[]' "$fixture/$profile.json")
  for owner in paid-inc laozhu beebat-dev; do
    mkdir -p "$HOME/Developer/$owner"
    cp "$repo_dir/home/.config/direnv/github.envrc" "$HOME/Developer/$owner/.envrc"
    direnv allow "$HOME/Developer/$owner/.envrc"
  done

  for owner in paid-inc laozhu beebat-dev ritchie-paid laozhu-other beebat-dev-other; do
    directory="$HOME/Developer/$owner/nested/repo"
    mkdir -p "$directory"
    git -C "$directory" init -q
    case "$profile:$owner" in
      home:* | work:laozhu | work:beebat-dev)
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
    actual_email="$(git -C "$directory" config user.email)"
    if [ "$actual_email" != "$email" ]; then
      printf '%s/%s: expected %s, got %s\n' "$profile" "$owner" "$email" "$actual_email" >&2
      exit 1
    fi
    test "$(git -C "$directory" config user.name)" = 'Ritchie Zhu'
    test "$(git -C "$directory" config core.sshCommand)" = "ssh -i ~/.ssh/$key -o IdentitiesOnly=yes"
    test "$(git -C "$directory" config gpg.format)" = ssh
    test "$(git -C "$directory" config --bool commit.gpgsign)" = true
    test "$(git -C "$directory" config user.signingkey)" = "~/.ssh/$key"
    git -C "$directory" commit --allow-empty -qm 'Verify automatic SSH signing'
    printf '%s namespaces="git" %s\n' "$email" "$(cat "$HOME/.ssh/$key.pub")" >"$fixture/allowed_signers"
    git -C "$directory" -c gpg.ssh.allowedSignersFile="$fixture/allowed_signers" verify-commit HEAD
    helper="$(git -C "$directory" config --get-all credential.https://github.com.helper | tail -1)"
    [[ "$helper" == *"/.config/$gh_config gh auth git-credential" ]]
    [[ "$helper" == *"env -u GH_TOKEN -u GITHUB_TOKEN "* ]]

    # Real clone setup must select the destination's key before contacting SSH.
    : >"$GIT_IDENTITY_TEST_LOG"
    if PATH="$fixture/bin:$PATH" git clone git@github.com:example/repo.git \
      "$HOME/Developer/$owner/cloned" >/dev/null 2>&1; then
      echo 'Mock SSH unexpectedly completed a clone' >&2
      exit 1
    fi
    grep -Fq -- "-i $HOME/.ssh/$key -o IdentitiesOnly=yes" "$GIT_IDENTITY_TEST_LOG"
  done
  # A repository outside Developer must also use the profile's default identity.
  mkdir -p "$HOME/GitHub/example"
  git -C "$HOME/GitHub/example" init -q
  if [ "$profile" = home ]; then email=laozhu.me@gmail.com; else email=204663844+ritchie-paid@users.noreply.github.com; fi
  test "$(git -C "$HOME/GitHub/example" config user.email)" = "$email"
done

# Only credential lookup is mocked: Git, Zsh and direnv execute real configuration.
cat >"$fixture/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
test -z "${GH_TOKEN+x}"
test -z "${GITHUB_TOKEN+x}"
if [ -n "${GH_FIXTURE_LOG:-}" ]; then printf '%s\n' "$*" >>"$GH_FIXTURE_LOG"; fi
case "$GH_CONFIG_DIR" in
  "$HOME/.config/gh-laozhu") actor=laozhu; token=fixture-personal-token ;;
  "$HOME/.config/gh") actor=ritchie-paid; token=fixture-work-token ;;
  *) exit 1 ;;
esac
case "$*" in
  'auth token')
    if [ -n "${GH_FIXTURE_LOGGED_OUT:-}" ]; then exit 1; fi
    if [ -n "${GH_FIXTURE_EMPTY_TOKEN:-}" ]; then exit 0; fi
    printf '%s\n' "$token"
    ;;
  'auth git-credential get')
    cat >/dev/null
    printf 'username=%s\npassword=%s\n' "$actor" "$token"
    ;;
  *) exit 1 ;;
esac
GH
chmod +x "$fixture/bin/gh"
export PATH="$fixture/bin:$PATH"

# Updating the checkout must not break the old out-of-store links before rebuild.
(
  export HOME="$fixture/before-rebuild" XDG_CONFIG_HOME="$fixture/before-rebuild/.config"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  mkdir -p "$HOME/.config/git" "$HOME/.config/direnv" "$HOME/GitHub/example" "$HOME/Developer/laozhu/repo"
  cp "$repo_dir/home/.gitconfig" "$HOME/.gitconfig"
  cp "$repo_dir/home/.config/git/laozhu.inc" "$HOME/.config/git/"
  cp "$repo_dir/home/.config/direnv/direnvrc" "$HOME/.config/direnv/direnvrc"
  git -C "$HOME/GitHub/example" init -q
  actual_email="$(git -C "$HOME/GitHub/example" config user.email || true)"
  if [ "$actual_email" != 204663844+ritchie-paid@users.noreply.github.com ]; then
    echo 'Pre-rebuild Git lost its existing default identity' >&2
    exit 1
  fi
  git -C "$HOME/Developer/laozhu/repo" init -q
  test "$(git -C "$HOME/Developer/laozhu/repo" config user.email)" = laozhu.me@gmail.com
  cp "$repo_dir/home/.config/direnv/github.envrc" "$HOME/Developer/laozhu/.envrc"
  direnv allow "$HOME/Developer/laozhu/.envrc"
  cd "$HOME/Developer/laozhu/repo"
  direnv exec . bash -e -c '
    test "$GH_CONFIG_DIR" = "$HOME/.config/gh-laozhu"
    test "$GITHUB_ACTOR" = laozhu
    test "$GITHUB_TOKEN" = fixture-personal-token
  '
)

for profile in home work; do
  export HOME="$fixture/$profile" XDG_CONFIG_HOME="$fixture/$profile/.config"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  cp "$fixture/$profile.direnvrc" "$HOME/.config/direnv/direnvrc"
  # Relocate Home Manager's absolute home paths to keep Zsh history in the fixture.
  sed "s|/Users/rich/|$HOME/|g" "$fixture/$profile.zshrc" >"$HOME/.zshrc"
  mkdir -p "$HOME/.config/paid-inc"
  printf 'export WORK_SECRET_LOADED=1\nexport GITHUB_TOKEN=fixture-secret-file-token\n' >"$HOME/.config/paid-inc/secrets.env"
  if [ "$profile" = home ]; then
    default_config="$HOME/.config/gh-laozhu"
    default_actor=laozhu
    default_token=fixture-personal-token
  else
    default_config="$HOME/.config/gh"
    default_actor=ritchie-paid
    default_token=fixture-work-token
  fi
  export DEFAULT_CONFIG="$default_config" DEFAULT_ACTOR="$default_actor" DEFAULT_TOKEN="$default_token"

  # Actual generated Zsh startup must replace another account's inherited state.
  (
    cd "$HOME"
    export GH_CONFIG_DIR=wrong-config GITHUB_ACTOR=wrong-actor
    export GH_TOKEN=fixture-inherited-override GITHUB_TOKEN=fixture-parent-token
    TERM=dumb zsh -f -e -c '
      source "$HOME/.zshrc"
      if [ "$GH_CONFIG_DIR" != "$DEFAULT_CONFIG" ]; then
        printf "Zsh startup: expected %s, got %s\n" "$DEFAULT_CONFIG" "$GH_CONFIG_DIR" >&2
        exit 1
      fi
      test "$GITHUB_ACTOR" = "$DEFAULT_ACTOR"
      test "$GITHUB_TOKEN" = "$DEFAULT_TOKEN"
      test -z "${GH_TOKEN+x}"
      test -z "${WORK_SECRET_LOADED+x}"
    '
  )
  # Stored-login failure and empty tokens must not preserve inherited credentials.
  for failure in GH_FIXTURE_LOGGED_OUT GH_FIXTURE_EMPTY_TOKEN; do
    (
      cd "$HOME"
      export "$failure=1" GH_TOKEN=fixture-inherited-override GITHUB_TOKEN=fixture-parent-token
      TERM=dumb zsh -f -e -c '
        source "$HOME/.zshrc"
        test "$GH_CONFIG_DIR" = "$DEFAULT_CONFIG"
        test "$GITHUB_ACTOR" = "$DEFAULT_ACTOR"
        test -z "${GH_TOKEN+x}"
        test -z "${GITHUB_TOKEN+x}"
      ' 2>"$fixture/login-warning"
      grep -Fq 'gh auth login' "$fixture/login-warning"
      if grep -Eq 'fixture-(parent-token|inherited-override)' "$fixture/login-warning"; then
        echo 'Login guidance exposed a token' >&2
        exit 1
      fi
    )
  done
  # Work Zsh reselects after cd: a shell opened in a personal tree must not keep that
  # account elsewhere, and cd within one account must not reread the token.
  if [ "$profile" = work ]; then
    (
      mkdir -p "$HOME/Developer/laozhu/a" "$HOME/Developer/beebat-dev/b" "$HOME/elsewhere"
      cd "$HOME/Developer/laozhu/a"
      export GH_FIXTURE_LOG="$fixture/gh-calls"
      : >"$GH_FIXTURE_LOG"
      TERM=dumb zsh -f -e -c '
        source "$HOME/.zshrc"
        test "$GITHUB_ACTOR" = laozhu
        test "$GITHUB_TOKEN" = fixture-personal-token
        cd "$HOME/Developer/beebat-dev/b"
        test "$GITHUB_ACTOR" = laozhu
        test "$(wc -l <"$GH_FIXTURE_LOG" | tr -d " ")" = 1
        cd "$HOME/elsewhere"
        test "$GH_CONFIG_DIR" = "$HOME/.config/gh"
        test "$GITHUB_ACTOR" = ritchie-paid
        test "$GITHUB_TOKEN" = fixture-work-token
        cd "$HOME/Developer/laozhu/a"
        test "$GH_CONFIG_DIR" = "$HOME/.config/gh-laozhu"
        test "$GITHUB_TOKEN" = fixture-personal-token
        test "$(wc -l <"$GH_FIXTURE_LOG" | tr -d " ")" = 3
      '
    )
  fi

  export GH_CONFIG_DIR="$default_config" GITHUB_ACTOR="$default_actor" GITHUB_TOKEN="$default_token"
  unset GH_TOKEN
  for owner in paid-inc laozhu beebat-dev ritchie-paid laozhu-other beebat-dev-other; do
    directory="$HOME/Developer/$owner/nested/repo"
    # An approved ancestor or an independent child .envrc must both work.
    if [ ! -f "$HOME/Developer/$owner/.envrc" ]; then
      cp "$repo_dir/home/.config/direnv/github.envrc" "$HOME/Developer/$owner/.envrc"
      direnv allow "$HOME/Developer/$owner/.envrc"
    fi
    case "$profile:$owner" in
      home:* | work:laozhu | work:beebat-dev)
        expected_config="$HOME/.config/gh-laozhu"
        expected_actor=laozhu
        expected_token=fixture-personal-token
        ;;
      *)
        expected_config="$HOME/.config/gh"
        expected_actor=ritchie-paid
        expected_token=fixture-work-token
        ;;
    esac
    export EXPECTED_CONFIG="$expected_config" EXPECTED_ACTOR="$expected_actor" EXPECTED_TOKEN="$expected_token"
    (
      cd "$directory"
      eval "$(direnv export bash)"
      test "$GH_CONFIG_DIR" = "$EXPECTED_CONFIG"
      test "$GITHUB_ACTOR" = "$EXPECTED_ACTOR"
      test "$GITHUB_TOKEN" = "$EXPECTED_TOKEN"
      test -z "${GH_TOKEN+x}"
      if [ "$profile:$owner" = work:paid-inc ]; then
        test "$WORK_SECRET_LOADED" = 1
      else
        test -z "${WORK_SECRET_LOADED+x}"
      fi
      test -z "${GIT_SSH_COMMAND+x}"
      cd "$HOME"
      eval "$(direnv export bash)"
      test "$GH_CONFIG_DIR" = "$DEFAULT_CONFIG"
      test "$GITHUB_ACTOR" = "$DEFAULT_ACTOR"
      test "$GITHUB_TOKEN" = "$DEFAULT_TOKEN"
      test -z "${WORK_SECRET_LOADED+x}"
    )
    printf 'export PROJECT_FLAG=1\n' >"$directory/.envrc"
    direnv allow "$directory/.envrc"
    (
      cd "$directory"
      export GH_TOKEN=fixture-inherited-override GITHUB_TOKEN=fixture-parent-token
      direnv exec . bash -e -c '
        test "$GH_CONFIG_DIR" = "$EXPECTED_CONFIG"
        test "$GITHUB_ACTOR" = "$EXPECTED_ACTOR"
        test "$GITHUB_TOKEN" = "$EXPECTED_TOKEN"
        test -z "${GH_TOKEN+x}"
        test "$PROJECT_FLAG" = 1
        test -z "${GIT_SSH_COMMAND+x}"
      '
    )
    # A new shell in an already selected directory must agree before its first prompt.
    (
      cd "$directory"
      eval "$(direnv export bash)"
      TERM=dumb zsh -f -e -c '
        source "$HOME/.zshrc"
        if [ "$GH_CONFIG_DIR" != "$EXPECTED_CONFIG" ]; then
          printf "Nested Zsh: expected %s, got %s\n" "$EXPECTED_CONFIG" "$GH_CONFIG_DIR" >&2
          exit 1
        fi
        test "$GITHUB_ACTOR" = "$EXPECTED_ACTOR"
        test "$GITHUB_TOKEN" = "$EXPECTED_TOKEN"
        test -z "${GH_TOKEN+x}"
      '
    )
    # HTTPS Git must use its selected helper even with conflicting token variables.
    credentials="$(printf 'protocol=https\nhost=github.com\n\n' |
      GH_TOKEN=fixture-inherited-override GITHUB_TOKEN=fixture-parent-token \
        git -C "$directory" credential fill)"
    grep -Fxq "username=$expected_actor" <<<"$credentials"
    grep -Fxq "password=$expected_token" <<<"$credentials"
    unset credentials

    (
      cd "$directory"
      export GH_FIXTURE_LOGGED_OUT=1 GH_TOKEN=fixture-inherited-override GITHUB_TOKEN=fixture-parent-token
      eval "$(direnv export bash 2>"$fixture/direnv-warning")"
      test -z "${GH_TOKEN+x}"
      if [ "$profile:$owner" = work:paid-inc ]; then
        test "$GITHUB_TOKEN" = fixture-secret-file-token
      else
        test -z "${GITHUB_TOKEN+x}"
        grep -Fq 'gh auth login' "$fixture/direnv-warning"
      fi
    )
  done
done
printf '%s\n' 'Git and GitHub CLI profile identity tests passed.'
