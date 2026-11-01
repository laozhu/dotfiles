# 多 GitHub 账号按目录自动切换

下面使用个人账号和工作账号作为占位，不包含真实用户名、邮箱、公钥或凭据。
将示例值替换为本机信息；真实账号配置、私钥和 OAuth 凭据只保留在本机。

目标是：`~/Developer/personal/` 和 `~/Developer/community/` 下的项目使用个人账号，
其他位置默认使用工作账号；Git、SSH、GitHub CLI 和提交签名分别选择对应身份。

## 1. 为账号准备独立 SSH key

保留已有 key。只有对应文件不存在时才生成新 key，并按提示设置口令：

```bash
ssh-keygen -t ed25519 -C "personal GitHub" -f ~/.ssh/id_ed25519_personal
ssh-keygen -t ed25519 -C "work GitHub" -f ~/.ssh/id_ed25519_work
```

把各自的 `.pub` 公钥添加到对应 GitHub 账号的 Settings → SSH and GPG keys，
用途选择 Authentication Key。无 `.pub` 后缀的文件是私钥，不上传或提交。
`IdentitiesOnly=yes` 可避免 SSH 尝试其他已加载 key，意外登录错误账号。

## 2. Git 按仓库目录选择身份

将默认配置合并到本机 `~/.gitconfig`，不要覆盖其他现有选项：

```gitconfig
[user]
  name = <WORK_NAME>
  email = work@example.invalid
  signingKey = ~/.ssh/id_ed25519_work
[core]
  sshCommand = ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes
[credential "https://github.com"]
  helper =
  helper = "!env GH_CONFIG_DIR=\"$HOME/.config/gh\" gh auth git-credential"
[includeIf "gitdir:~/Developer/personal/"]
  path = ~/.config/git/personal.inc
[includeIf "gitdir:~/Developer/community/"]
  path = ~/.config/git/personal.inc
```

本机 `~/.config/git/personal.inc`：

```gitconfig
[user]
  name = <PERSONAL_NAME>
  email = personal@example.invalid
  signingKey = ~/.ssh/id_ed25519_personal
[core]
  sshCommand = ssh -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes
[credential "https://github.com"]
  helper =
  helper = "!env GH_CONFIG_DIR=\"$HOME/.config/gh-personal\" gh auth git-credential"
```

空 `helper` 清除之前继承的 helper，再指定对应账号的 GitHub CLI 凭据，
避免 HTTPS push/pull 从系统钥匙串取到另一个账号的凭据。

`gitdir:` 的末尾 `/` 匹配整个目录树，不会误匹配 `personal-other`。
Git 根据实际 Git 目录选择身份，linked worktree 跟随其主仓库的 Git 目录。
仓库 local config、显式的 `GIT_SSH_COMMAND` 等仍可覆盖这些默认值。

## 3. GitHub CLI 为账号保留独立登录配置

SSH key 用于 Git 传输认证，不能代替 GitHub CLI 的 API 登录。
默认配置目录 `~/.config/gh` 留给工作账号，个人账号使用 `~/.config/gh-personal`。
分别完成登录，并用 `gh api user` 确认账号：

```bash
GH_CONFIG_DIR="$HOME/.config/gh" gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key
GH_CONFIG_DIR="$HOME/.config/gh" gh api user --jq .login

GH_CONFIG_DIR="$HOME/.config/gh-personal" gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key
GH_CONFIG_DIR="$HOME/.config/gh-personal" gh api user --jq .login
```

GitHub CLI 默认尝试把凭据保存在系统凭据存储中，例如 macOS 钥匙串。
不要把实际 gh 配置目录、OAuth token 或私钥加入 dotfiles。

不要在进出目录时调用 `gh auth switch`：它会修改该配置目录的全局活动账号，
影响其他终端。使用不同的 `GH_CONFIG_DIR` 可让两个账号并行工作。

## 4. direnv 自动选择 GitHub CLI 配置

启用 direnv 的 Shell hook。Zsh 使用：

```zsh
eval "$(direnv hook zsh)"
```

在 `~/.config/direnv/direnvrc` 中合并以下片段，让项目自带独立 `.envrc` 时也能选择身份：

```bash
case "$PWD/" in
  "$HOME/Developer/personal/"* | "$HOME/Developer/community/"*)
    export GH_CONFIG_DIR="$HOME/.config/gh-personal"
    ;;
esac
```

在两个父目录分别创建内容为 `:` 的 `.envrc`，触发目录环境加载，然后允许它们：

```bash
direnv allow ~/Developer/personal/.envrc
direnv allow ~/Developer/community/.envrc
```

进入对应目录时自动加载个人账号配置，离开时恢复之前的环境。
子项目新增自己的 `.envrc` 时仍需审查并单独允许。未加载 Shell hook 的脚本，
先进入目标目录，再执行 `direnv exec . gh ...`。

这里只为 gh 设置环境变量，不导出 `GIT_SSH_COMMAND`；Git 自行按仓库目录选择 key，
避免在个人目录执行 `git -C /其他仓库 ...` 时，环境变量覆盖目标仓库的 SSH 配置。

`GH_TOKEN`、`GITHUB_TOKEN` 会优先于存储的登录凭据，其中 `GH_TOKEN` 优先级更高。
已有交互式登录通常不需要设置它们；全局固定 token 可能使目录账号选择失效。

## 5. 自动签名并显示 Verified

在 `~/.gitconfig` 中合并：

```gitconfig
[gpg]
  format = ssh
[commit]
  gpgSign = true
```

`user.signingKey` 会随前面的 Git 条件配置选择。普通 `git commit` 自动使用相应私钥签名。
若私钥有口令，可通过 ssh-agent 保存解锁状态；不要把口令写进配置或脚本。

GitHub 的 Authentication Key 和 Signing Key 是两个独立用途，同一公钥需要分别登记。
可以在 GitHub Settings 中再添加一次公钥，选择 Signing Key；也可以对两个账号分别执行：

```bash
# 以下命令示例对应个人账号；工作账号改用默认配置目录及工作 key。
GH_CONFIG_DIR="$HOME/.config/gh-personal" gh auth refresh --hostname github.com --scopes admin:ssh_signing_key
GH_CONFIG_DIR="$HOME/.config/gh-personal" gh api user --jq .login
# 确认上一条输出的账号正确，再上传。
GH_CONFIG_DIR="$HOME/.config/gh-personal" gh ssh-key add ~/.ssh/id_ed25519_personal.pub --type signing --title "macOS commit signing"
```

提交邮箱必须满足对应账号的邮箱验证要求。推送新的有效签名提交后，GitHub 才会显示 Verified。
设置不会给旧提交自动补签；不要为补 badge 重写已共享的历史。
本地 `git verify-commit` 另需配置 allowed signers 文件，GitHub 的验证不依赖该本地文件。

## 检查与排错

在不同目录分别检查，避免只凭账号头像判断：

```bash
git config --show-origin user.email
git config --show-origin core.sshCommand
git config --show-origin user.signingKey
git config --bool commit.gpgSign
direnv exec . gh api user --jq .login
```

没有 `.envrc` 的默认目录直接运行 `gh api user --jq .login`。
SSH 认证可单独检查：

```bash
ssh -T -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes git@github.com
```

GitHub 的成功欢迎信息通常伴随退出码 1。若 push 报 403，先核对 gh 的实际账号；
若 commit 显示 Unverified，检查 Signing Key 登记、提交邮箱及是否真的生成了签名。

## 官方参考

- [Git 条件配置与 includeIf](https://git-scm.com/docs/git-config)
- [GitHub 多账号管理](https://docs.github.com/en/account-and-profile/how-tos/account-management/managing-multiple-accounts)
- [GitHub CLI 环境变量](https://cli.github.com/manual/gh_help_environment)
- [direnv Shell 集成](https://direnv.net/docs/hook.html)
- [GitHub 提交签名配置](https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key)
