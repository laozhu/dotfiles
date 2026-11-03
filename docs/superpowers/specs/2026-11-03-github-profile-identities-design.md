# Profile-specific GitHub identities

The user approved the approach described in chat on 2026-11-03: Nix selects
the default GitHub identity by machine profile, and only work enables directory
exceptions. This extends the existing profile already passed to Home Manager.

## Behavior

| Directory                      | work         | home   |
| ------------------------------ | ------------ | ------ |
| Default, including `~/GitHub/` | ritchie-paid | laozhu |
| `~/Developer/paid-inc/`        | ritchie-paid | laozhu |
| `~/Developer/laozhu/`          | laozhu       | laozhu |
| `~/Developer/beebat-dev/`      | laozhu       | laozhu |

Apply the same identity to Git email, SSH commit signing, SSH transport,
GitHub HTTPS credential helpers, and the managed shell's GitHub CLI environment.
Keep the shared Git author name, `Ritchie Zhu`.

Existing account details remain unchanged:

- ritchie-paid: `204663844+ritchie-paid@users.noreply.github.com`,
  `~/.ssh/id_ed25519`, and `~/.config/gh`.
- laozhu: `laozhu.me@gmail.com`, `~/.ssh/id_ed25519_laozhu`,
  and `~/.config/gh-laozhu`.

## Approaches

1. **Selected: generate profile-dependent configuration through Home Manager.**
   Reuse the existing Nix profile argument, share account fragments, and retain
   Git's native conditional includes for work. Applying identity configuration
   requires rebuild, consistently with other generated settings.
2. Separate complete home/work configurations would duplicate shared settings.
3. Runtime profile-file selection would require additional Git indirection and
   could disagree with the activated Nix generation.

## Configuration boundaries

- Separate common Git settings from account fragments. Generate the root Git
  configuration with the selected default include and work-only directory
  includes. Preserve other Home Manager Git settings, including LFS. Keep the
  legacy out-of-store Git and direnv sources intact so updating the checkout
  cannot break an old generation before rebuild.
- Configure the shell's default `GH_CONFIG_DIR` and `GITHUB_ACTOR` from Nix.
  Make direnv profile-aware so home never selects the work account or loads
  `~/.config/paid-inc/secrets.env`. Keep work's current directory behavior,
  including independently approved nested `.envrc` files.
- Automatic identity selection must remove inherited `GH_TOKEN` overrides and
  resolve the selected account's stored token without inherited token variables.
  Home must discard an inherited `GITHUB_TOKEN` when personal login is missing,
  and report how to log in rather than silently using a work token. Preserve
  work's intentional `secrets.env` fallback within its work directory.
- Leave credentials and private keys local. Do not migrate, delete, or switch
  stored logins, and do not use `gh auth switch` on directory changes.
- Keep profile selection in bootstrap/rebuild unchanged. Do not infer a profile
  from paths, hostnames, or account login state.

Repository-local Git settings and explicitly supplied command environment
variables remain user overrides. The managed shell environment does not control
GUI processes that do not inherit it. Existing terminals must be reopened after
activation. Linked worktrees retain Git's existing Git-directory matching rules.

## Acceptance

Test both evaluated Nix configurations using temporary homes and generated test
keys. Home tests must work with only the personal key present. Verify actual Git
identity, signing, clone SSH selection, and HTTPS helper behavior; verify shell
startup and direnv entry/exit, nested `.envrc`, directory-prefix boundaries,
inherited token overrides, and logged-out behavior without displaying tokens.

Run `bash tests/run.sh` and build both Darwin configurations with `--no-link`.
Do not activate either configuration as validation. Real account login, GUI
environment inheritance, and fresh-machine setup remain manual acceptance work.
