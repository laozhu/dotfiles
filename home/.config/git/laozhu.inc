[user]
  email = laozhu.me@gmail.com
  signingKey = ~/.ssh/id_ed25519_laozhu
[core]
  sshCommand = ssh -i ~/.ssh/id_ed25519_laozhu -o IdentitiesOnly=yes
[credential "https://github.com"]
  helper =
  helper = !env GH_CONFIG_DIR="$HOME/.config/gh-laozhu" gh auth git-credential
