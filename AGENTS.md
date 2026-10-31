# Project notes for agents

Apple Silicon macOS configuration using nix-darwin, Home Manager and Homebrew.
The flake host is `mac`. See [configuration maintenance](docs/configuration.md)
for file ownership and update workflows, and [SFM operations](docs/sing-box.md) for proxy changes.

## Intentional decisions

- Access to GitHub, Homebrew and other download services requires a working proxy
  in the user's network. Keep SFM connected during downloads; check proxy connectivity
  before treating fetch failures as package or configuration problems.
- `homebrew.onActivation.cleanup = "zap"` is intentional. Declare Homebrew packages
  in `configuration.nix`; do not weaken cleanup to preserve undeclared installations.
- Determinate manages the Nix daemon, so `nix.enable = false` is intentional.
- Keep the official macOS binary sources defined in `macos-binaries.nix` and the
  Homebrew Codex cask. Do not silently fall back to source builds or change package managers.
- SFM owns the proxy runtime and TUN. Do not add another sing-box service or process.
  Edit the repository template and SOPS ciphertext, not the generated plaintext or SFM container.
- `home/AGENTS.md` contains global preferences deployed to other projects.
  Keep dotfiles-specific guidance here; `CLAUDE.md` only imports this file.

## Verification

Run relevant tests with `bash tests/run.sh`. For Nix changes, also run
`nix build --no-link .#darwinConfigurations.mac.system` to build without activating.
Do not use bootstrap or rebuild merely as validation: they change the live machine.
Tests and builds do not verify a fresh macOS installation or application permissions.

## Maintaining this file

Keep only project knowledge useful across sessions. Link to authoritative files instead
of duplicating their contents. Prefer pruning or rewriting to appending rules.
