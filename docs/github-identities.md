# GitHub 目录身份

| 仓库位置 | Git / GitHub 账号 | 提交邮箱 | SSH key |
| --- | --- | --- | --- |
| `~/Developer/laozhu/` 下 | laozhu | laozhu.me@gmail.com | `~/.ssh/id_ed25519_laozhu` |
| `~/Developer/beebat-dev/` 下 | laozhu | laozhu.me@gmail.com | `~/.ssh/id_ed25519_laozhu` |
| 其他位置 | ritchie-paid | 204663844+ritchie-paid@users.noreply.github.com | `~/.ssh/id_ed25519` |

Git 的公共配置位于 `home/.gitconfig` 和 `home/.config/git/laozhu.inc`，
通过原生 `includeIf gitdir:` 选择身份、SSH key 和 GitHub HTTPS credential helper。
因此 Git 在非交互终端运行时也能选择对应仓库的身份。条件按真实 Git 目录匹配，
linked worktree 跟随其主仓库的 Git 目录。仓库自己的 local config 和显式环境变量仍可覆盖默认值。
已有提交的作者不会因配置变化而被重写。

GitHub CLI 的 API 请求需要 OAuth，不能用 SSH key 代替登录：

- ritchie-paid 继续使用默认 `~/.config/gh`，凭据保留在系统钥匙串。
- laozhu 使用独立的 `~/.config/gh-laozhu`，也通过系统钥匙串保存凭据。
- 两个开发目录的 `.envrc` 启用 direnv；`~/.config/direnv/direnvrc` 为目录内的
  `gh` 设置 `GH_CONFIG_DIR`。项目有自己的 `.envrc` 时同样适用。
  SSH clone 的 key 由 Git 按目标仓库目录选择，不导出会覆盖其他仓库配置的 `GIT_SSH_COMMAND`。
- 离开目录时 direnv 恢复原来的环境，不通过 `gh auth switch` 改变另一个终端的账号。
- 显式传入的 `GH_TOKEN` / `GITHUB_TOKEN` 仍按 gh 官方规则优先于存储的 OAuth 凭据。

## 新机启用

配置由 Home Manager 部署。私钥和 OAuth 凭据不受仓库管理，不复制其他机器的私钥。
若 laozhu 的 key 尚不存在，可交互生成：

```bash
ssh-keygen -t ed25519 -C laozhu@github.com -f ~/.ssh/id_ed25519_laozhu
```

允许两个已审查的父目录 `.envrc`：

```bash
direnv allow ~/Developer/laozhu/.envrc
direnv allow ~/Developer/beebat-dev/.envrc
```

在 laozhu 目录中完成一次登录，并上传公钥；先确认登录账号：

```bash
cd ~/Developer/laozhu
direnv exec . gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key --scopes admin:public_key
direnv exec . gh api user --jq .login
# 上一条必须输出 laozhu，之后再上传。
direnv exec . gh ssh-key add ~/.ssh/id_ed25519_laozhu.pub --title "laozhu macOS"
```

普通终端会通过已有的 direnv shell hook 自动选择账号；脚本或未加载 hook 的终端，
先进入目标目录再使用 `direnv exec . gh ...`。项目自带的新 `.envrc` 仍需单独审查并允许。

## 检查

```bash
cd ~/Developer/laozhu/dotfiles
git config user.email
git config core.sshCommand
direnv exec . gh api user --jq .login

cd ~
git config user.email
gh api user --jq .login
```

新密钥上传后可用 `ssh -T -i ~/.ssh/id_ed25519_laozhu -o IdentitiesOnly=yes git@github.com`
验证服务端识别为 laozhu。GitHub 的成功欢迎信息通常伴随退出码 1，这是该测试命令的正常行为。

## 提交签名与 Verified

两个账号都启用 `gpg.format = ssh` 和 `commit.gpgSign = true`，普通 `git commit`
会自动签名。默认使用 `~/.ssh/id_ed25519`，两个 laozhu 目录使用
`~/.ssh/id_ed25519_laozhu`，与 SSH 登录的 key 保持一致。

GitHub 的 Authentication key 和 Signing key 是两种独立登记用途。
同一个公钥需要额外登记为 Signing key；首次配置分别在对应账号上下文执行：

```bash
# laozhu
cd ~/Developer/laozhu
direnv exec . gh auth refresh --hostname github.com --scopes admin:ssh_signing_key
direnv exec . gh api user --jq .login
direnv exec . gh ssh-key add ~/.ssh/id_ed25519_laozhu.pub --type signing --title "laozhu macOS commit signing"

# ritchie-paid
cd ~
gh auth refresh --hostname github.com --scopes admin:ssh_signing_key
gh api user --jq .login
gh ssh-key add ~/.ssh/id_ed25519.pub --type signing --title "ritchie-paid macOS commit signing"
```

每次上传前确认 `gh api user` 输出的账号正确。提交者邮箱须属于该账号，
并满足 GitHub 的邮箱验证要求。新签名提交推送后由 GitHub 验证并显示 Verified；
配置不会为已有的无签名提交补签，也不会重写历史。

本地签名是否有效可用临时 allowed signers 文件验证；GitHub 的 Verified 不依赖本机的
allowed signers 文件。规则或仓库 local config 可以覆盖自动签名默认值。
官方步骤见 [GitHub SSH 签名配置](https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key)。
