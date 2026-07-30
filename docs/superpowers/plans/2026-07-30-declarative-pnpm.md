# Declarative pnpm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install pnpm declaratively in the Home Manager user environment.

**Architecture:** Add the existing nixpkgs `pnpm` package to the runtime section of `home.packages`. Keep package resolution pinned by the repository's existing `flake.lock` and introduce no mutable npm, Corepack, wrapper, or activation state.

**Tech Stack:** Determinate Nix, nix-darwin, Home Manager, nixpkgs

## Global Constraints

- Only implementation file modified: `home.nix`.
- Use the existing `pkgs.pnpm` top-level nixpkgs package.
- Keep `pkgs.pnpm` between `pkgs.nodejs_26` and `pkgs.bun`.
- Do not add wrapper scripts, activation hooks, npm prefix settings, Corepack configuration, Flake inputs, or modules.

---

### Task 1: Add pnpm to the user environment

**Files:**
- Modify: `home.nix`

**Interfaces:**
- Consumes: `pkgs.pnpm` from the nixpkgs revision pinned by `flake.lock`.
- Produces: a `pnpm` executable in the Home Manager user profile after `./rebuild.sh`.

- [ ] **Step 1: Verify the current evaluated package list lacks pnpm**

Run:

```bash
nix eval --json \
  '.#darwinConfigurations.mac.config.home-manager.users.rich.home.packages' |
  jq -e 'map(tostring) | any(.[]; test("-pnpm-"))'
```

Expected: exit status 1 because the evaluated Home Manager package list does not contain pnpm.

- [ ] **Step 2: Add the minimal declaration**

Change the runtime dependency section of `home.nix` to:

```nix
    pkgs.nodejs_26
    pkgs.pnpm
    pkgs.bun
```

- [ ] **Step 3: Verify the evaluated package list contains pnpm**

Run:

```bash
nix eval --json \
  '.#darwinConfigurations.mac.config.home-manager.users.rich.home.packages' |
  jq -e 'map(tostring) | any(.[]; test("-pnpm-"))'
```

Expected: `true` and exit status 0.

- [ ] **Step 4: Verify the complete configuration builds**

Run:

```bash
git diff --check
nix flake check
nix build --no-link .#darwinConfigurations.mac.system
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add home.nix
git commit -m "feat: install pnpm with Home Manager"
```

- [ ] **Step 6: Activate and verify after merge**

Run:

```bash
./rebuild.sh
pnpm --version
```

Expected: rebuild succeeds and pnpm prints the version supplied by the pinned nixpkgs package.
