# Test Suite Organization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic, inaccurately named sing-box test file with focused executable tests and one suite entrypoint.

**Architecture:** Split the existing shell file at responsibility boundaries without changing assertions. Each test resolves the repository root itself; `tests/run.sh` discovers no tests dynamically and invokes the explicit ordered list.

**Tech Stack:** Bash, jq, Node.js, Nix, sing-box

## Global Constraints

- Preserve every existing assertion and failure path.
- Do not add a shared test framework.
- Do not stage unrelated working-tree changes.

---

### Task 1: Split the monolithic test

**Files:**
- Delete: `tests/sing-box-static.sh`
- Create: `tests/check-sops-age-key.sh`
- Create: `tests/bootstrap.sh`
- Create: `tests/prefetch-uu-booster.sh`
- Create: `tests/rebuild.sh`
- Create: `tests/repository-policy.sh`
- Create: `tests/sing-box-config.sh`
- Create: `tests/render-sing-box-config.sh`
- Create: `tests/publish-sing-box-config.sh`

**Interfaces:**
- Consumes: repository files through a root derived from `BASH_SOURCE[0]`.
- Produces: eight independently executable test scripts with exit code 0 on success.

- [ ] **Step 1: Record the existing suite result**

Run: `bash tests/sing-box-static.sh`
Expected: `sing-box static checks passed`

- [ ] **Step 2: Move each contiguous responsibility block**

Give every created file this header:

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
```

- [ ] **Step 3: Run every split test independently**

Run: `for test_file in tests/*.sh; do bash "$test_file"; done`
Expected: every command exits 0.

### Task 2: Add the suite entrypoint

**Files:**
- Create: `tests/run.sh`
- Modify: `docs/superpowers/plans/2026-07-26-sing-box-macos-client.md`

**Interfaces:**
- Consumes: explicit ordered test script names.
- Produces: `bash tests/run.sh`, the canonical full-suite command.

- [ ] **Step 1: Add an explicit runner**

The runner resolves its own directory, prints `==> <name>` and invokes every test with Bash.

- [ ] **Step 2: Replace active full-suite commands in documentation**

Replace `bash tests/sing-box-static.sh` commands with `bash tests/run.sh` while leaving historical file-creation descriptions intact.

- [ ] **Step 3: Verify from outside the repository**

Run: `(cd /tmp && bash /Users/rich/GitHub/laozhu/dotfiles/tests/run.sh)`
Expected: all named tests pass.

### Task 3: Verify and commit

**Files:**
- Test: all files under `tests/`

**Interfaces:**
- Consumes: the completed test suite.
- Produces: a reviewed commit containing only the test reorganization and its documentation.

- [ ] **Step 1: Run syntax and full-suite checks**

Run: `bash -n tests/*.sh && bash tests/run.sh`
Expected: exit 0.

- [ ] **Step 2: Check stale references and Git scope**

Run: `rg 'bash tests/sing-box-static.sh' .` and `git diff --check`
Expected: no active command references and no whitespace errors.

- [ ] **Step 3: Commit**

```bash
git add tests docs/superpowers/specs/2026-08-12-test-suite-organization-design.md docs/superpowers/plans/2026-08-12-test-suite-organization.md docs/superpowers/plans/2026-07-26-sing-box-macos-client.md
git commit -m "refactor: organize shell test suite"
```
