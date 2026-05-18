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
7. **(Confirmation required)** Sets Homebrew zsh as the default login shell
8. Prompts for and saves a GitHub Personal Access Token to the macOS Keychain (used by `.zshrc`)

### Usage

```sh
yadm bootstrap                  # interactive (default-no on dangerous prompts)
yadm bootstrap --yes            # auto-approve all prompts (or BOOTSTRAP_YES=1)
yadm bootstrap --dry-run        # trace what would happen, no changes made
yadm bootstrap --help           # show all flags
```

### Providing the GitHub token non-interactively

Step 8 prompts for a GitHub PAT with hidden input. To skip the prompt (e.g. for unattended runs), export `GITHUB_TOKEN` first — bootstrap will pick it up and save it to the Keychain:

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
| Runtime | Node.js, Bun, Deno, Python |
| Git | git-delta (side-by-side diffs), tig, gh |
| File Navigation | eza, fd, fzf, ripgrep, television, yazi, zoxide |
| Data | jq, yq, qsv, xan |
| Containers | Podman, Podman Compose, kubectl |
| AI | Gemini CLI |
| Media | ffmpeg, yt-dlp, gallery-dl, you-get |
| Publishing | pandoc, hugo, zola, tectonic, mermaid-cli, dprint |
| Benchmark | hyperfine |
| Networking | httpie, sing-box, xh |
| Security | age, gnupg, pass |
| Other | bat, btop, duf, ncdu, qrencode, rsync, tealdeer, mo, im-select |

### Apps (Homebrew Casks)

| Category | Apps |
|---|---|
| Terminal | Ghostty |
| Editor / IDE | VS Code, Obsidian |
| Browser | Google Chrome |
| Containers | Podman Desktop |
| AI | Claude, Claude Code, Codex, Codex App, Google Gemini |
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

## sing-box

`~/.config/sing-box/config.json` contains server secrets (UUID, public key, short ID), so it's tracked through [yadm encrypt](https://yadm.io/docs/encryption) instead of as plain text. The path is listed in `~/.config/yadm/encrypt`, and the encrypted bundle lives at `~/.config/yadm/archive` (which IS committed). The plain `config.json` itself stays gitignored.

### Decrypting on a new machine

After `yadm clone`, the encrypted archive is checked out but the actual `config.json` doesn't exist yet. Run:

```sh
yadm decrypt
```

yadm will prompt for the symmetric passphrase used when the archive was created and extract `~/.config/sing-box/config.json` (and any other files listed in `~/.config/yadm/encrypt`) into place. Verify it parses:

```sh
sing-box check -c ~/.config/sing-box/config.json
```

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

### Regenerating the secrets on the server

If you need fresh credentials, run these on the xray server and update the matching fields in `config.json`:

```sh
xray uuid                  # → UUID
xray x25519                # → PUBLIC_KEY (use the "Password" / public key line)
openssl rand -hex 8        # → SHORT_ID
```

`SERVER_DOMAIN` is whatever DNS A/AAAA record you've pointed at the server.

### Run at boot on macOS

sing-box is installed via Homebrew (`brew install sing-box`). The TUN inbound needs root, so it runs as a **LaunchDaemon** (system-wide) rather than a LaunchAgent (per-user) — you must use `sudo brew services` so the plist lands in `/Library/LaunchDaemons/` instead of `~/Library/LaunchAgents/`:

```sh
sudo brew services start sing-box
```

This creates `/Library/LaunchDaemons/homebrew.mxcl.sing-box.plist` and launches the daemon. Homebrew points it at `/opt/homebrew/etc/sing-box/config.json`, which is a symlink to `~/.config/sing-box/config.json` — so editing the dotfile here is what the daemon actually reads.

Manage:

```sh
sudo launchctl kickstart -k system/homebrew.mxcl.sing-box   # restart (after config edit)
sudo launchctl print     system/homebrew.mxcl.sing-box      # full status
sudo brew services list                                     # one-line status of all brew services
sudo brew services restart sing-box                         # equivalent to kickstart -k
sudo brew services stop    sing-box                         # stop + unload
```

View logs via Apple's unified logging (the Homebrew plist doesn't redirect stdout/stderr to a file):

```sh
log stream --predicate 'process == "sing-box"' --level info
```

Uninstall: `sudo brew services stop sing-box` (the plist is removed automatically).

### Web dashboard

The config enables sing-box's Clash-compatible API on `127.0.0.1:9090` with a bundled dashboard. Once the daemon is running, open:

```
http://localhost:9090/ui
```

From there you can switch outbound modes, inspect live connections, view per-rule traffic, and ping outbounds. The dashboard assets are downloaded on first launch via the `🇸🇬 aws-singapore-hy2` outbound (see `external_ui_download_detour` in the config — pinned to a specific hy2 outbound rather than `🌐 Proxy-Auto` to avoid the startup-time concurrent-handshake burst that can trigger Reality's anti-detection drops).

### Foreground run

To run in the foreground for easier debugging instead:

```sh
sudo sing-box run -c ~/.config/sing-box/config.json
```

## License

MIT
