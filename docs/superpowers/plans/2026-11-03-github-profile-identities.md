# Profile-specific GitHub identities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Preserve work's directory identities and make home use laozhu globally.

**Architecture:** Home Manager selects account includes and shell defaults from
its existing profile argument. Git and direnv retain their native mechanisms;
credentials remain in the existing local account directories.

**Tech Stack:** Nix, Home Manager, Git, Bash/Zsh, direnv, GitHub CLI.

**Spec:** [Approved approach and design](../specs/2026-11-03-github-profile-identities-design.md).

## Global Constraints

- Only work enables directory exceptions; home uses laozhu in every directory.
- Keep the shared Git author name, `Ritchie Zhu`.
- Leave credentials and private keys local.
- Keep profile selection in bootstrap/rebuild unchanged.
- Do not activate either configuration as validation.
- Use one agent; do not push or change the live machine as part of implementation.

## Review Focus

- Home has no work key or work login: Git and gh must use personal configuration.
- Inherited `GH_TOKEN` must not override automatically selected account identity.
- A missing personal login must not preserve a work token on home.
- Directory exit and nested `.envrc` must preserve profile-specific defaults.
- `laozhu-other` and `beebat-dev-other` must not match work's personal exceptions.

### Task 1: Profile-selected Git identities

**Files:** Modify `home.nix` and `tests/git-identities.sh`; create
`home/.config/git/common.inc` and `home/.config/git/ritchie-paid.inc`; retain
`home/.config/git/laozhu.inc` and the legacy `home/.gitconfig` entry point.

**Interfaces:** Consume the existing `profile` argument. Produce generated
`~/.gitconfig` selecting one shared account fragment plus work-only conditional
includes. Preserve the existing fragment paths and Home Manager Git settings.

- [x] Extend the identity fixture to consume each profile's evaluated Git
      configuration; assert the spec's email, key, and helper directory across all
      four directory classes and similarly prefixed directories. Home creates only
      `id_ed25519_laozhu`. Exercise real signed commits and mocked clone transport.
- [x] Run `bash tests/git-identities.sh`; confirm home fails because the current
      generated configuration still selects the work identity outside personal trees.
- [x] Extract the existing work identity into its own fragment, retain common
      settings, and generate the selected include order in `home.nix`.
- [x] Run the Git fixture for both profiles; expect the full identity matrix,
      signed commits, clone key selection, and HTTPS helper assertions to pass.

### Task 2: Profile-selected GitHub CLI environment

**Files:** Modify `home.nix` and `tests/git-identities.sh`; add
`home/.config/direnv/work-secrets.envrc` and `scripts/github-token.sh`. Retain the
legacy `home/.config/direnv/direnvrc` source for pre-rebuild compatibility.

**Interfaces:** Consume `profile`, the existing gh configuration directories,
and directory rules from the spec. Produce matching `GH_CONFIG_DIR`,
`GITHUB_ACTOR`, and selected `GITHUB_TOKEN` for managed shells and direnv.

- [x] Add tests for actual generated Zsh initialization and direnv selection,
      covering home/work defaults, work-only secrets loading, independently approved
      nested `.envrc`, directory entry/exit, inherited tokens, and missing logins.
      Use a fake gh only for credential lookup; never query or print real tokens.
- [x] Run the tests; confirm home selection and inherited-token cases fail for
      the expected reasons before changing shell behavior.
- [x] Generate shell defaults and profile-aware direnv configuration. Remove
      inherited `GH_TOKEN` during automatic selection, resolve stored credentials
      without token overrides, clear home fallback tokens on missing login, and
      retain work's explicit secrets-file fallback.
- [x] Run `bash tests/git-identities.sh`; expect all Git, Zsh, and direnv cases
      to pass. Ensure missing-login diagnostics contain login guidance, never tokens.
      Verify that updating the checkout preserves old Git and direnv behavior until
      a new generation is activated.

### Task 3: Documentation and final verification

**Files:** Modify `docs/configuration.md`, `docs/github-identities.md`, and the
profile description in `README.md`.

**Interfaces:** Document the generated behavior delivered by Tasks 1 and 2,
existing login directories, rebuild requirement, and process-environment limits.

- [x] Replace instructions to manually edit managed Git/direnv files with the
      profile behavior and correct login commands; retain useful SSH key guidance.
- [x] Run `bash tests/run.sh`; expect `All tests passed.`
- [x] Run `nix build --no-link .#darwinConfigurations.home.system .#darwinConfigurations.work.system`;
      expect exit status 0 without activation.
- [x] Review the complete diff against the spec, run `git diff --check`, and
      report remaining manual acceptance checks. Leave implementation reviewable;
      committing, pushing, or activating requires the user's requested scope.
