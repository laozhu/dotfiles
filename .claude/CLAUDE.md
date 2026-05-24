# User-global instructions

## Merging PRs

When I say "merge" (e.g. "merge #123"), run directly:

```
gh pr merge <pr> --squash --admin --delete-branch
```

No strategy question, no second confirmation. **Exception:** if CI is red in a way that looks like a real regression tied to the diff (failing test, type error, build failure — not a flake), surface it and ask before force-merging.

## Commit messages and PR descriptions

No AI attribution. No `Generated with Claude Code`, no `🤖`, no `Co-Authored-By: Claude`. Write as if I authored them.

## GitHub CLI account

Under `~/Developer/paid-inc/` (paid-ui, web-app, admin-app, configuration-service, html-to-pdf-lambda, super-contract-pdf-lambda, super-contract-html-lambda), the active `gh` account must be `ritchie-paid` — the `laozhu` account lacks access to the `Settld-io` org and `gh` will fail with "Could not resolve to a Repository".

Before any `gh` command in those repos, check `gh auth status` and switch proactively if needed:

```
gh auth switch --user ritchie-paid
```

## Preferred CLIs (use instead of system defaults)

When a task calls for the left-hand tool, use the right-hand one. If unsure it's installed, `command -v <name>`.

| Instead of | Use | Notes |
|---|---|---|
| `find` | `fd` | |
| `grep` | `rg` (Grep tool) | |
| `curl` (human requests) | `xh` | use `curl` only when scripting needs its exact flags |
| `curl` to api.github.com | `gh` | |
| `curl` to Atlassian REST | `acli` | Jira / Confluence / Bitbucket |
| `awk`/`cut` on CSV | `xan` (small) / `qsv` (large) | |
| `pdflatex` / `xelatex` | `tectonic` | |
| `df` | `duf` | |
| `du \| sort` | `ncdu` | interactive — only if needed |
| `top` | `btop` | interactive — only if needed |
| `time` loops | `hyperfine` | benchmarking |
| `node` / `npm` (one-shot) | `bun` | unless project pins another |

**Also available, no system equivalent:**

| Tool | Purpose | Notes |
|---|---|---|
| `jq` | JSON query/transform | |
| `yq` | YAML/TOML/XML query/transform | |
| `pandoc` | Document conversion | |
| `magick` | ImageMagick — image ops | |
| `svgo` | SVG minify | |
| `mmdc` | Mermaid diagram render | |
| `ffmpeg` | Any audio/video op | |
| `yt-dlp` | YouTube/Bilibili download | `--cookies-from-browser chrome:Default`; `-f 'bv*[height<=720][ext=mp4]+ba[ext=m4a]/b[height<=720]'` for 720p MP4 |
| `gallery-dl` | Image galleries | |
| `you-get` | yt-dlp fallback for niche CN sites | |
| `dprint` | Multi-lang formatter | |
