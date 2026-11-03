# Sourced by generated Zsh and direnv configuration after selecting an account.
# A work-directory secrets.env may supply a fallback token before this runs.
unset GH_TOKEN
if github_token="$(env -u GH_TOKEN -u GITHUB_TOKEN gh auth token 2>/dev/null)" && [ -n "$github_token" ]; then
  export GITHUB_TOKEN="$github_token"
elif [ -z "${GITHUB_TOKEN:-}" ]; then
  unset GITHUB_TOKEN
  printf 'GitHub account %s is not logged in. Run: GH_CONFIG_DIR="%s" gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key\n' \
    "$GITHUB_ACTOR" "$GH_CONFIG_DIR" >&2
fi
unset github_token
