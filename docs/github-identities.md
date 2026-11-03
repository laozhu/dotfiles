# GitHub 身份与机器 profile

Git、SSH、提交签名和 GitHub CLI 的默认身份由机器 profile 决定。
`~/.config/dotfiles/profile` 仍是 bootstrap/rebuild 的唯一选择来源，不按目录或登录状态推断 profile。

| 目录                      | work         | home   |
| ------------------------- | ------------ | ------ |
| 默认，包括 `~/GitHub/`    | ritchie-paid | laozhu |
| `~/Developer/paid-inc/`   | ritchie-paid | laozhu |
| `~/Developer/laozhu/`     | laozhu       | laozhu |
| `~/Developer/beebat-dev/` | laozhu       | laozhu |

home 只需个人账号的密钥和 gh 登录，不需要准备工作账号。
work 保留两个账号；目录名末尾的 `/` 保证规则不会匹配 `laozhu-other` 等相似名称。

## 配置归属与生效

`home.nix` 按 profile 生成 `~/.gitconfig`、`~/.config/direnv/direnvrc` 和 Zsh 初始化代码。
公共 Git 设置在 `home/.config/git/common.inc`，两个账号分别使用该目录下的身份片段。
work 的 direnv secrets 加载规则在 `home/.config/direnv/work-secrets.envrc`。
修改这些配置后运行 `./rebuild.sh` 并重新打开终端，不直接编辑生成文件。
profile 同时影响软件安装及身份配置；不要为了临时切换账号修改机器 profile。
旧入口 `home/.gitconfig` 和 `home/.config/direnv/direnvrc` 保留给尚未 rebuild 的机器，
新配置不再引用它们，避免更新仓库后、rebuild 前立即改变旧软链接的行为。

| 账号         | 提交邮箱                                          | SSH 与签名密钥             | gh 配置目录           |
| ------------ | ------------------------------------------------- | -------------------------- | --------------------- |
| ritchie-paid | `204663844+ritchie-paid@users.noreply.github.com` | `~/.ssh/id_ed25519`        | `~/.config/gh`        |
| laozhu       | `laozhu.me@gmail.com`                             | `~/.ssh/id_ed25519_laozhu` | `~/.config/gh-laozhu` |

提交作者名共用 `Ritchie Zhu`。私钥、OAuth 登录及本机 secrets 不纳入仓库，
rebuild 不生成密钥、不迁移凭据，也不调用 `gh auth switch` 修改存储的活动账号。

Git 原生按 Git 目录选择身份，不依赖 direnv 是否已允许。
linked worktree 跟随其主仓库的 Git 目录。仓库 local config 和显式的
`GIT_SSH_COMMAND` 仍可覆盖默认设置。
HTTPS credential helper 会清除继承的 token，再使用所选账号的 gh 登录。

## 准备 SSH key

保留已有 key。仅在对应文件不存在时生成，并按提示设置口令：

```bash
# home 和 work 都需要个人 key。
ssh-keygen -t ed25519 -C "laozhu GitHub" -f ~/.ssh/id_ed25519_laozhu
# 只有 work 需要工作 key。
ssh-keygen -t ed25519 -C "ritchie-paid GitHub" -f ~/.ssh/id_ed25519
```

把各自的 `.pub` 公钥添加到对应账号的 GitHub Settings → SSH and GPG keys，
用途选择 Authentication Key。无 `.pub` 后缀的文件是私钥，不上传或提交。
`IdentitiesOnly=yes` 限定 Git 使用所选 key。

普通 `git commit` 自动以 SSH key 签名。同一公钥还需登记为 Signing Key，
GitHub 才能验证提交签名；有口令的私钥可通过 ssh-agent 保存解锁状态。
可在 GitHub Settings 中登记，或使用下方命令。先确认输出的账号，再上传公钥：

```bash
env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/gh-laozhu" \
  gh auth refresh --hostname github.com --scopes admin:ssh_signing_key
env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/gh-laozhu" gh api user --jq .login
env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/gh-laozhu" \
  gh ssh-key add ~/.ssh/id_ed25519_laozhu.pub --type signing --title "macOS commit signing"
```

work 的工作账号改用 `~/.config/gh` 和 `~/.ssh/id_ed25519.pub`。
提交邮箱需满足对应账号的邮箱验证要求。设置不会给旧提交补签；
本地 `git verify-commit` 另需 allowed signers 文件，GitHub 验证不依赖该本地文件。

## 登录 GitHub CLI

SSH key 不能代替 gh 的 API 登录。home 只执行个人账号登录；work 额外登录工作账号。
显式检查其他账号时清除当前 Shell 的 token，避免 token 优先级覆盖指定的配置目录：

```bash
# 个人账号，预期输出 laozhu。
env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/gh-laozhu" \
  gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key
env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/gh-laozhu" gh api user --jq .login

# 仅 work：工作账号，预期输出 ritchie-paid。
env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/gh" \
  gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key
env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/gh" gh api user --jq .login
```

GitHub CLI 尝试把凭据保存在系统凭据存储中，例如 macOS 钥匙串。
已经登录的机器沿用现有配置目录，无需因本次配置变更重新登录。

## Shell 与 direnv

Zsh 启动时选择对应 profile 和当前目录的身份，设置 `GH_CONFIG_DIR`、
`GITHUB_ACTOR`，并从所选 gh 登录读取 `GITHUB_TOKEN`。
work 在两个个人目录中启动嵌套 Shell 时，也立即使用个人身份。
work 的 Zsh 每次 `cd` 后重新选择，在个人目录打开的终端离开后会切回工作账号；
账号未变化时不重新读取 token。
`GITHUB_ACTOR` 供其他工具使用，本身不决定 gh 的认证身份。

Home Manager 为三个 `~/Developer/` 父目录部署触发用 `.envrc`，
Shell hook 已启用。首次使用需审查并允许相应文件：

```bash
direnv allow ~/Developer/paid-inc/.envrc
direnv allow ~/Developer/laozhu/.envrc
direnv allow ~/Developer/beebat-dev/.envrc
```

进入目录时 direnv 应用相同的账号选择，离开时恢复进入前的环境。
子项目独立 `.envrc` 也会选择身份，但仍需单独审查和允许。
只有 work 在 `~/Developer/paid-inc/` 下自动加载本机
`~/.config/paid-inc/secrets.env`；home 即使进入该目录也不加载工作 secrets。

`GH_TOKEN` 优先于 `GITHUB_TOKEN`，两者都优先于存储的登录凭据。
自动选择身份时会清除继承的两个 token，再读取对应登录，避免另一个账号的 token 残留。
work 的工作目录可使用 secrets 文件中的 `GITHUB_TOKEN` 作为 gh 未登录时的回退；
home 没有这个回退。找不到可用 token 时会提示登录，不沿用继承的工作 token。
读取过程不打印或持久化 token。

单次命令显式提供的 token、项目 `.envrc` 后续设置的变量仍属于主动覆盖。
已有终端不会自动刷新；GUI 应用未继承 Shell 环境时也不受这套 Shell 初始化控制。
未加载 hook 的脚本可先进入已允许的目录，再执行 `direnv exec . gh ...`。
不导出 `GIT_SSH_COMMAND`，避免 Shell 所在目录干扰 `git -C` 的目标仓库。

## 检查与排错

在不同目录分别检查，不输出 token：

```bash
git config --show-origin user.email
git config --show-origin core.sshCommand
git config --show-origin user.signingKey
git config --bool commit.gpgSign
gh api user --jq .login
```

有 `.envrc` 而未加载 hook 时，使用 `direnv exec . gh api user --jq .login`。
SSH 认证可单独检查：

```bash
ssh -T -i ~/.ssh/id_ed25519_laozhu -o IdentitiesOnly=yes git@github.com
```

GitHub 的成功欢迎信息通常伴随退出码 1。若 push 报 403，先核对实际账号；
若提交显示 Unverified，检查 Signing Key、邮箱及提交是否包含签名。

## 官方参考

- [Git 条件配置与 includeIf](https://git-scm.com/docs/git-config)
- [GitHub 多账号管理](https://docs.github.com/en/account-and-profile/how-tos/account-management/managing-multiple-accounts)
- [GitHub CLI 环境变量](https://cli.github.com/manual/gh_help_environment)
- [direnv Shell 集成](https://direnv.net/docs/hook.html)
- [GitHub 提交签名配置](https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key)
