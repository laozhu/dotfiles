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
    ├── zellij/              # Zellij terminal multiplexer config
    ├── dprint.json          # Dprint code formatter config
    └── starship.toml        # Starship prompt theme
```

## Prerequisites

- macOS
- [Homebrew](https://brew.sh/)
- [yadm](https://yadm.io/) (`brew install yadm`)

## Setup

Clone the dotfiles into your home directory:

```sh
yadm clone https://github.com/laozhu/dotfiles.git
```

## Homebrew

### Install packages from Brewfile

Install all packages, casks, and VS Code extensions defined in `~/.Brewfile`:

```sh
brew bundle --global
```

Or specify the file explicitly:

```sh
brew bundle --file=~/.Brewfile
```

### Dump current packages to Brewfile

Save your currently installed packages back to the Brewfile:

```sh
brew bundle dump --global --force
```

The `--force` flag overwrites the existing `.Brewfile`. Without it, the command will fail if the file already exists.

To include descriptions as comments:

```sh
brew bundle dump --global --force --describe
```

## Key Tools

| Category | Tools |
|---|---|
| Shell | zsh, Oh My Zsh, Starship, zsh-autosuggestions, zsh-syntax-highlighting |
| Terminal | Ghostty, Zellij |
| Editor | Vim, VS Code |
| Git | git-delta (side-by-side diffs), tig, gh |
| File Navigation | eza, fd, fzf, ripgrep, television, yazi, zoxide |
| Containers | Podman, Podman Compose, kubectl |
| AI | Claude Code, Codex, Gemini CLI, GitHub Copilot |
| Media | ffmpeg, yt-dlp, gallery-dl, you-get |
| Other | bat, btop, duf, httpie, jq, yq, pandoc, hugo, zola |

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
