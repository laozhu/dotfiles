# dotfiles

macOS dotfiles managed with [yadm](https://yadm.io/).

## What's Included

```
~
├── .Brewfile                # Homebrew packages, casks, and VS Code extensions
├── .gitconfig               # Git config (delta, signed commits, rebase workflow)
├── .zshrc                   # Zsh shell (Oh My Zsh, Starship, aliases)
├── .claude/                 # Claude Code settings and scripts
│   ├── settings.json
│   ├── fetch-usage.sh
│   ├── statusline.sh
│   └── plugins/
│       └── installed_plugins.json   # tracked: marketplace plugin manifest
└── .config/
    ├── bat/                 # Bat (cat replacement) config
    ├── btop/                # Btop system monitor config
    ├── ghostty/             # Ghostty terminal config
    ├── sing-box/            # sing-box proxy config (config.json encrypted via yadm)
    ├── television/          # Television fuzzy finder config
    ├── yadm/
    │   └── bootstrap        # macOS provisioning script (runs after yadm clone)
    ├── zellij/              # Zellij terminal multiplexer config
    ├── dprint.json          # Dprint code formatter config
    └── starship.toml        # Starship prompt theme
```

## Prerequisites

- macOS
- [Homebrew](https://brew.sh/)
- [yadm](https://yadm.io/) (`brew install yadm`)

## Setup

Clone the dotfiles into your home directory. yadm will offer to run the bootstrap script automatically:

```sh
yadm clone https://github.com/laozhu/dotfiles.git
```

## Bootstrap

The bootstrap script (`~/.config/yadm/bootstrap`) provisions a fresh macOS to match this repo. It is idempotent — safe to re-run.

What it does:

1. Installs Xcode Command Line Tools (if missing)
2. Installs Homebrew (if missing)
3. Runs `brew bundle --global` to install everything in `~/.Brewfile`
4. Installs Oh My Zsh (without overwriting the tracked `.zshrc`)
5. Wires up fzf key bindings and completions
6. Updates the tealdeer (`tldr`) cache
7. Installs Playwright browser binaries and Claude skill (`playwright-cli install` / `--skills`)
8. Re-adds Claude plugin marketplaces and installs all plugins, then installs standalone skills (`larksuite/cli`, `mattpocock/skills`) via `npx skills add`
9. **(Confirmation required)** Sets Homebrew zsh as the default login shell
10. Prompts for and saves a GitHub Personal Access Token to the macOS Keychain (used by `.zshrc`)

### Usage

`yadm bootstrap` does **not** forward extra argv to the script — pass options
via env vars, or invoke the script directly.

```sh
yadm bootstrap                                    # interactive (default-no on dangerous prompts)
BOOTSTRAP_YES=1 yadm bootstrap                    # auto-approve all prompts
BOOTSTRAP_DRY_RUN=1 yadm bootstrap                # trace what would happen, no changes made

~/.config/yadm/bootstrap --dry-run                # equivalent direct invocation
~/.config/yadm/bootstrap --yes                    # equivalent direct invocation
~/.config/yadm/bootstrap --help                   # show all flags
```

### Providing the GitHub token non-interactively

Step 10 prompts for a GitHub PAT with hidden input. To skip the prompt (e.g. for unattended runs), export `GITHUB_TOKEN` first — bootstrap will pick it up and save it to the Keychain:

```sh
GITHUB_TOKEN=ghp_xxx yadm bootstrap --yes
```

Or pipe from a secret manager:

```sh
GITHUB_TOKEN=$(op read 'op://Personal/GitHub PAT/credential') yadm bootstrap --yes
```

To add or rotate the token later without re-running bootstrap:

```sh
security add-generic-password -s 'github-token' -a "$USER" -w <YOUR_TOKEN>
```

## Homebrew

### Install or update packages from Brewfile

```sh
brew bundle --global
```

### Dump current packages to Brewfile

Save your currently installed packages back to the Brewfile:

```sh
brew bundle dump --global --force
```

The `--force` flag overwrites the existing `.Brewfile`. Without it, the command will fail if the file already exists.

## Key Tools

### CLI Tools (Homebrew Formulas)

| Category | Tools |
|---|---|
| Shell | zsh, Oh My Zsh, Starship, zsh-autosuggestions, zsh-syntax-highlighting |
| Multiplexer | Zellij |
| Editor | Vim |
| Runtime | Node.js, Bun, Python, pnpm |
| Git | git-delta (side-by-side diffs), tig, gh, act |
| File Navigation | eza, fd, fzf, ripgrep, television, yazi, zoxide |
| Data | jq, yq, qsv, xan |
| Containers | Podman, Podman Compose, kubectl |
| AI | Gemini CLI, Lark CLI |
| Browser Automation | playwright-cli |
| Media | ffmpeg, yt-dlp, gallery-dl, you-get |
| Images | imagemagick, svgo |
| Publishing | pandoc, hugo, zola, tectonic, mermaid-cli, dprint |
| Benchmark | hyperfine |
| Networking | httpie, sing-box, xh, iperf3, miniserve |
| Security | age, gnupg, pass |
| SaaS | acli (Atlassian), googleworkspace-cli, sentry-cli |
| Other | bat, btop, duf, ncdu, rsync, tealdeer, mo, im-select |

### Apps (Homebrew Casks)

| Category | Apps |
|---|---|
| Terminal | Ghostty |
| Editor / IDE | VS Code, Obsidian |
| Browser | Google Chrome |
| Containers | Podman Desktop |
| AI | Claude, Claude Code, Codex, Codex App, Google Gemini, cc-switch |
| Cloud | gcloud CLI |
| Communication | Discord, WeChat, WhatsApp, Feishu (Lark) |
| Media | QQ Music |
| Productivity | Google Drive |
| Fonts | JetBrains Mono Nerd Font |
| Peripherals | Logitech G HUB |
| Other | Bambu Studio (3D printing) |

## Claude Code Skills & Plugins

Third-party extensions loaded into Claude Code, grouped by install source. Plugin manifests live in `~/.claude/plugins/installed_plugins.json` (tracked by yadm); standalone skills live under `~/.claude/skills/`.

### Plugins (`/plugin` marketplaces)

**[`claude-plugins-official`](https://github.com/anthropics/claude-plugins-official)**

| Plugin | Purpose |
|---|---|
| `superpowers` | Core workflow skills (TDD, debugging, brainstorming, plans, git worktrees) |
| `frontend-design` | Opinionated frontend UI generation |
| `skill-creator` | Author and benchmark new skills |
| `claude-md-management` | Audit / improve / revise CLAUDE.md files |
| `claude-code-setup` | Recommend hooks, subagents, MCP servers for a repo |
| `commit-commands` | `/commit`, `/commit-push-pr`, branch cleanup |
| `pr-review-toolkit` | Multi-agent PR review (style, tests, comments, types, silent failures) |
| `code-modernization` | Legacy-code discovery, brief, transform, harden |
| `mcp-server-dev` | Build MCP servers / apps / MCPBs |
| `chrome-devtools-mcp` | Browser debugging via Chrome DevTools MCP |
| `typescript-lsp` | LSP-backed TS navigation |
| `context7` | Up-to-date library docs lookup |
| `greptile` | Semantic codebase search |
| `playground` | Interactive single-file HTML explorers |
| `hyperframes` | Motion graphics / video composition |
| `expo` | Expo / React Native workflows |
| `resend` | Email composition + Resend API |
| `discord` | Discord channel as Claude chat surface |
| `security-guidance` | Defensive security guidance |
| `learning-output-style` | Educational interactive output style |

**[`openai-codex`](https://github.com/openai/codex-plugin-cc)** — `codex` (delegate to Codex CLI for rescue / second-opinion runs)

**[`understand-anything`](https://github.com/Lum1104/Understand-Anything)** — `understand-anything` (knowledge-graph codebase analysis + dashboard)

### Standalone skills (`~/.claude/skills/`)

**[`larksuite/cli`](https://github.com/larksuite/cli)** — Lark/Feishu suite: IM, mail, docs, sheets, base, calendar, tasks, VC, minutes, and other workspace integrations.

**[`mattpocock/skills`](https://github.com/mattpocock/skills)** — Matt Pocock's engineering workflow skills: TDD, diagnose, prototype, triage, grill-me, zoom-out, and more.

**[`microsoft/playwright`](https://github.com/microsoft/playwright)** — Playwright browser automation skill, installed by bootstrap step 7 via `playwright-cli install --skills`.

### Reinstalling on a fresh machine

Bootstrap step 8 re-adds the three marketplaces, installs every plugin listed above, and runs `npx skills add larksuite/cli` + `npx skills add mattpocock/skills` for the standalone skills. The `playwright-cli` skill is handled separately in step 7. All commands are idempotent — safe to re-run after `yadm clone` or whenever this list changes.

## Notable Shell Aliases

```sh
ll          # eza -al with icons
tree        # eza tree view (3 levels)
fvim        # fuzzy-find then open in vim
brewup      # update + upgrade + cleanup brew
docker      # aliased to podman
tmux        # aliased to zellij
sb-status   # sing-box LaunchDaemon status
sb-reload   # reload sing-box after editing config
```

## sing-box

### Install & run

- Installed via Homebrew: `brew install sing-box`.
- Runs as a **LaunchDaemon**: `sudo brew services start sing-box`. The TUN inbound needs root, so a per-user LaunchAgent won't work.
- Config path: Homebrew reads `/opt/homebrew/etc/sing-box/config.json`, which is symlinked to `~/.config/sing-box/config.json`. Edit the dotfile — the daemon picks it up.
- Uninstall: `sudo brew services stop sing-box`.

### Daily use

| Task | Command |
|---|---|
| Status / reload after edit | `sb-status` / `sb-reload` (aliases in `.zshrc`) |
| Tail logs | `log stream --predicate 'process == "sing-box"' --level info` |
| Debug interactively | Stop the daemon, then `sudo sing-box run -c ~/.config/sing-box/config.json` |
| Validate config | `sing-box check -c ~/.config/sing-box/config.json` |

### Dashboard

The Clash-compatible API is exposed on `127.0.0.1:9090` with a bundled dashboard at <http://localhost:9090/ui> — switch outbound modes, inspect live connections, ping outbounds.

Dashboard assets are downloaded on first launch via the `🇸🇬 aws-singapore-hy2` outbound. The config pins `external_ui_download_detour` to that specific hy2 outbound (rather than `🌐 Proxy-Auto`) to avoid the startup-time concurrent-handshake burst that can trigger Reality's anti-detection drops.

### Secrets (encrypted via yadm)

`~/.config/sing-box/config.json` contains server secrets (UUID, public key, short ID), so it's tracked through [yadm encrypt](https://yadm.io/docs/encryption) instead of plain text:

- `~/.config/yadm/encrypt` — lists which paths to encrypt.
- `~/.config/yadm/archive` — the encrypted bundle (committed).
- `config.json` itself — gitignored.

On a new machine after `yadm clone`, run `yadm decrypt` to extract `config.json` (prompts for the symmetric passphrase), then verify with `sing-box check`.

### Updating secrets and re-encrypting

After editing `config.json` on any machine, regenerate the archive and commit it:

```sh
yadm encrypt                                      # regenerate ~/.config/yadm/archive
yadm add ~/.config/yadm/archive
yadm commit -m "sing-box: rotate secrets"
yadm push
```

On other machines, pull and re-decrypt:

```sh
yadm pull && yadm decrypt
```

## License

MIT
