# Software profiles

Implement the confirmed shared/work/home software groups using one JSON catalog.
Nix consumes its package identifiers; the read-only inventory script consumes its
names, types, installation sources and executable/application probes.
Keep existing Nix base tools but hide their rows using `inventory: false`, as requested. System and
Home Manager settings remain in their existing modules. Kotlin is provided by
project Gradle plugins; Bitdefender remains a company-managed manual requirement.
Homebrew's default OpenJDK is used, as requested.

Expose `darwinConfigurations.home` and `.work`. Require a valid local profile in
`~/.config/dotfiles/profile` before bootstrap/rebuild; bootstrap accepts
`--profile home|work` to initialize it. Refuse accidental profile replacement.
Keep `mac` as a compatibility alias of home for existing package references.
UU prefetch runs only for home. Keep Homebrew cleanup="zap".

Implementation and checks:

1. Add failing profile-selection and inventory tests, then implement the shared
   selector and catalog-based Markdown/JSON inventory. Check missing/invalid
   profiles, application receipts without apps, partial CLI availability and
   Python/Java system stubs. Never execute software or read secrets to detect it.
2. Drive Nix/Homebrew packages from the catalog. Add pinned official taps for mo,
   Atlassian and NordPass; configure Homebrew Python/JDK paths and Git LFS/direnv.
   Check both profiles' evaluated package lists and exclusion boundaries.
3. Wire bootstrap/rebuild, update their failure-order tests, and mark this machine
   home. Update README, project notes and CI references where needed.
4. Run format/check, full unit tests, no-activation builds of both profiles and
   the real inventory. No bootstrap/rebuild activation or automatic commit/push.
