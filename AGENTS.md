# Project notes for agents

Apple Silicon macOS configuration using nix-darwin, Home Manager and Homebrew.
The flake hosts are `home` and `work`; `mac` remains a compatibility alias for home. See [configuration maintenance](docs/configuration.md)
for file ownership and update workflows, and [SFM operations](docs/sing-box.md) for proxy changes.

## Intentional decisions

- Access to GitHub, Homebrew and other download services requires a working proxy
  in the user's network. Keep SFM connected during downloads; check proxy connectivity
  before treating fetch failures as package or configuration problems.
- `homebrew.onActivation.cleanup = "zap"` is intentional. Declare Homebrew packages
  in `software.json`; do not weaken cleanup to preserve undeclared installations.
- Determinate manages the Nix daemon, so `nix.enable = false` is intentional.
- Keep the official macOS binary sources defined in `macos-binaries.nix` and the
  Homebrew Codex cask. Do not silently fall back to source builds or change package managers.
- Prefer official macOS binaries, Nix substitutes and Homebrew bottles over source compilation.
  `nix-caches.conf` adds the signed upstream sops-nix cache to bootstrap, rebuild and CI.
  Keep signature checks enabled. Unpacking binaries and generating configuration still use Nix builds.
- SFM owns the proxy runtime and TUN. Do not add another sing-box service or process.
  Edit the repository template and SOPS ciphertext, not the generated plaintext or SFM container.
- `home/AGENTS.md` contains global preferences deployed to other projects.
  Keep dotfiles-specific guidance here; `CLAUDE.md` only imports this file.
- Software groups and inventory metadata live in `software.json`. Scripts read the local
  `~/.config/dotfiles/profile`; never infer or silently switch it. Keep home/work exclusions.

## Verification

Run relevant tests with `bash tests/run.sh`. For Nix changes, also run
`nix build --no-link .#darwinConfigurations.home.system .#darwinConfigurations.work.system` to build without activating.
Do not use bootstrap or rebuild merely as validation: they change the live machine.
Tests and builds do not verify a fresh macOS installation or application permissions.

## Maintaining this file

Keep only project knowledge useful across sessions. Link to authoritative files instead
of duplicating their contents. Prefer pruning or rewriting to appending rules.
