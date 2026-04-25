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
│   └── statusline.sh
└── .config/
    ├── bat/                 # Bat (cat replacement) config
    ├── btop/                # Btop system monitor config
    ├── ghostty/             # Ghostty terminal config
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
7. **(Confirmation required)** Sets Homebrew zsh as the default login shell

### Usage

```sh
yadm bootstrap                  # interactive (default-no on dangerous prompts)
yadm bootstrap --yes            # auto-approve all prompts (or BOOTSTRAP_YES=1)
yadm bootstrap --dry-run        # trace what would happen, no changes made
yadm bootstrap --help           # show all flags
```

### Manual secret setup

The `.zshrc` reads a GitHub token from the macOS Keychain. Add it once:

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
| Runtime | Node.js, Bun, Deno, Python, Ruby |
| Git | git-delta (side-by-side diffs), tig, gh |
| File Navigation | eza, fd, fzf, ripgrep, television, tree, yazi, zoxide |
| Data | jq, yq, qsv, xan |
| Containers | Podman, Podman Compose, kubectl |
| AI | Gemini CLI |
| Media | ffmpeg, yt-dlp, gallery-dl, you-get |
| Publishing | pandoc, hugo, zola, tectonic, mermaid-cli, dprint |
| Benchmark | hyperfine |
| Networking | httpie, xh |
| Security | age, gnupg, pass |
| Other | bat, btop, duf, qrencode, rsync, tealdeer, mo, im-select |

### Apps (Homebrew Casks)

| Category | Apps |
|---|---|
| Terminal | Ghostty, cmux (terminal for AI agents) |
| Editor / IDE | VS Code, Obsidian, Trae |
| Browser | Google Chrome |
| Containers | Podman Desktop |
| AI | Claude, Claude Code, Codex, Codex App, Conductor (Claude Code parallel sessions) |
| Networking | ngrok |
| Communication | Discord, WeChat |
| Media | QQ Music |
| Productivity | Google Drive |
| Fonts | JetBrains Mono Nerd Font |
| Other | Bambu Studio (3D printing) |

## Notable Shell Aliases

```sh
ll          # eza -al with icons
tree        # eza tree view (3 levels)
fvim        # fuzzy-find then open in vim
brewup      # update + upgrade + cleanup brew
docker      # aliased to podman
tmux        # aliased to zellij
```

## License

MIT
