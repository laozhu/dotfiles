[user]
  email = 204663844+ritchie-paid@users.noreply.github.com
  signingKey = ~/.ssh/id_ed25519
[core]
  sshCommand = ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes
[credential "https://github.com"]
  helper =
  helper = !env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/gh" gh auth git-credential
