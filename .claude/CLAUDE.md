# User-global instructions

## GitHub CLI account

For any repo under `~/Developer/paid-inc/` (e.g. `paid-ui`, `web-app`, `admin-app`, `configuration-service`, `html-to-pdf-lambda`, `super-contract-pdf-lambda`, `super-contract-html-lambda`), the active `gh` CLI account MUST be `ritchie-paid`.

The other account on this machine (`laozhu`) does not have access to the `Settld-io` GitHub org, so `gh` commands fail with "Could not resolve to a Repository" when it's active.

Before running any `gh` command in a paid-inc repo, check `gh auth status`. If the active account is not `ritchie-paid`, run:

```
gh auth switch --user ritchie-paid
```

Do this proactively rather than waiting for the GraphQL error.

## Preferred third-party CLIs (use these instead of system defaults)

The following Homebrew-installed CLIs are available on this machine. **Prefer them over the system defaults** for the matching task — they are faster, produce better output, or handle edge cases the defaults miss. Do not fall back to the default unless the third-party tool is genuinely unavailable.

### File search & navigation
- `fd` — fast, ergonomic file finder. **Replaces `find`.**
- `fzf` — interactive fuzzy finder for piping any list selection.
- `zoxide` — smart `cd` that jumps to frecency-ranked dirs. **Replaces `cd`** for known paths.
- `yazi` — terminal file manager (use only when interactive browsing helps).

### Text / data processing
- `jq` — JSON query and transform.
- `yq` — YAML/TOML/XML query and transform (same syntax family as jq).
- `xan` — fast CSV toolkit (slice, select, join, stats). **Replaces ad-hoc `awk`/`cut` on CSV.**
- `qsv` — high-performance CSV swiss-army knife (use for large CSVs / SQL-on-CSV).
- `pandoc` — universal document converter (md ↔ docx ↔ html ↔ pdf ↔ etc.).
- `tectonic` — modern self-contained LaTeX → PDF engine. **Replaces `pdflatex`/`xelatex`.**

### HTTP / network
- `xh` — fast, friendly HTTP client (Rust rewrite of HTTPie). **Replaces `curl`** for human-readable requests; use `curl` only when scripting needs its exact flags.
- `httpie` (`http`) — alternative HTTP client; use if `xh` is missing.
- `gh` — GitHub API/PR/issue operations. **Replaces hand-rolled `curl` to api.github.com.**
- `acli` — Atlassian CLI for Jira / Confluence / Bitbucket (issues, pages, repos). **Replaces hand-rolled `curl` to Atlassian REST APIs.**

### Image generation & processing
- `imagemagick` (`magick`) — convert, resize, composite, format-shift raster images.
- `svgo` — minify and clean SVG files.
- `mermaid-cli` (`mmdc`) — render Mermaid diagrams to SVG/PNG/PDF from text.

### Video / audio processing
- `ffmpeg` — transcode, trim, concat, extract frames, mux/demux audio & video. **The** tool for any video/audio operation.
- `gallery-dl` — download images/galleries from many sites.
- `yt-dlp` — **first choice** for YouTube and Bilibili. Use `--cookies-from-browser chrome:Default` (pin the profile) and `-f 'bv*[height<=720][ext=mp4]+ba[ext=m4a]/b[height<=720]'` for 720p MP4.
- `you-get` — fallback only, when `yt-dlp` lacks an extractor for the target site (occasionally useful for niche CN platforms).

### Code / dev workflow
- `rg` (ripgrep, via Claude Code's Grep tool) — already preferred; do not use `grep`.
- `dprint` — fast multi-language code formatter (JSON, MD, TS, TOML, etc.).
- `git-delta` — syntax-highlighted git diff pager (auto-used by git when configured).
- `hyperfine` — statistical command-line benchmarking. **Replaces ad-hoc `time` loops.**
- `tig` — ncurses git history browser (interactive only).
- `bun` — JS/TS runtime + package manager + bundler; prefer over `node`/`npm` for one-shot scripts and installs when the project doesn't pin another tool.

### System inspection (use only when output is actually needed)
- `duf` — disk usage overview. **Replaces `df`.**
- `ncdu` — interactive directory size analyzer. **Replaces `du | sort`.**
- `btop` — process/resource monitor. **Replaces `top`.**

### Rule
When a task calls for `find`, `curl`, `df`, `du`, `top`, `time`, `pdflatex`, or hand-parsing CSV with `awk`, stop and use the third-party replacement above. If unsure whether a tool is installed, check with `command -v <name>` before falling back.
