# sing-box macOS Client Configuration Design

Date: 2026-07-26

## Objective

Build a declarative sing-box client configuration for Apple Silicon macOS that:

- uses SFM as the only sing-box runtime;
- enables Network Extension TUN with IPv4 and IPv6;
- routes GFWList traffic through a proxy and leaves unmatched traffic direct;
- prevents DNS pollution with FakeIP and DNS hijacking;
- supports four outbounds across two servers and two protocols;
- lets SFM automatically select or manually switch nodes;
- permits explicit custom reject, direct, and proxy rules;
- keeps server credentials encrypted in Git with sops-nix and age;
- uses one shared nix-darwin configuration for all Macs;
- never starts multiple sing-box instances.

## Constraints

- The installed stable core is sing-box 1.13.14.
- SFM is the only component allowed to start or stop sing-box.
- Home Manager must not create a sing-box LaunchAgent or LaunchDaemon.
- The sing-box CLI is used only for configuration validation.
- No Web Dashboard or Clash API is required.
- The repository already has unrelated staged and unstaged changes. Implementation must preserve them.
- The old plaintext configuration is migration input only and must not be copied wholesale.
- The old configuration contains sensitive values and must never be printed in logs, tests, or documentation.

## Repository Layout

The repository will contain:

```text
.sops.yaml
secrets/
└── sing-box.yaml
home/.config/sing-box/
└── config.json
```

The responsibilities are:

- `.sops.yaml` contains the shared age public recipient and SOPS creation rules.
- `secrets/sing-box.yaml` contains only SOPS-encrypted secret values.
- `home/.config/sing-box/config.json` contains the complete non-secret configuration structure, the official JSON Schema reference, and named secret placeholders.
- `~/.config/sing-box/config.json` is the validated, rendered runtime configuration with mode `0600`.

The repository `config.json` is the only source of truth for configuration structure and rules. The SOPS file is only the encrypted data source. The SFM Local Profile is a derived runtime copy and must not become an independent editing source.

## Nix Architecture

### Single Darwin Configuration

`flake.nix` will expose one configuration:

```text
darwinConfigurations.mac
```

The duplicate `mac-laptop` and `mac-desktop` outputs will be removed. Both physical Macs will use the same configuration and the same shared age private key.

### Packages and Applications

Home Manager will install these command-line packages from nixpkgs:

- `age`
- `sops`
- `sing-box`

The nix-darwin Homebrew cask list will include:

- `sfm`

Declaring SFM is required because Homebrew activation uses `cleanup = "zap"`.

### Runtime Ownership

SFM owns:

- the only running sing-box instance;
- the macOS Network Extension;
- TUN lifecycle;
- logs and runtime status;
- outbound selector state;
- node latency tests and manual switching.

Home Manager owns:

- packages;
- encrypted secret provisioning;
- configuration rendering;
- file permissions;
- static and semantic configuration validation.

Home Manager must not run `sing-box run`, create an auto-start service, or restart SFM.

## Secret Management

### Encryption Model

sops-nix will use age as its encryption backend. The two Macs share one age identity.

The age private key is stored locally at:

```text
~/Library/Application Support/sops/age/keys.txt
```

Required permissions:

- containing directory: `0700`;
- private key: `0600`.

The private key must never be committed. It must be restored to a new Mac through a password manager, encrypted removable storage, or another secure out-of-band channel.

The following files are safe and expected to be committed:

- `.sops.yaml`, which contains only the age public recipient;
- `secrets/sing-box.yaml`, whose values are encrypted;
- the non-secret configuration template.

### Encrypted Fields

Migration will extract sensitive values from `/Users/rich/Downloads/config.json` without displaying them. Encrypted fields include:

- US and Singapore server addresses where treated as private deployment metadata;
- VLESS UUIDs;
- VLESS REALITY server names, public keys, and short IDs;
- Hysteria2 passwords;
- Hysteria2 Salamander obfuscation passwords;
- Hysteria2 TLS server names.

Ports and bandwidth settings may remain in the template unless inspection shows a reason to treat them as secret.

### Rendering

The repository configuration uses unique string placeholders. During Home Manager activation, sops-nix:

1. reads the SOPS ciphertext;
2. decrypts values using the local age identity;
3. substitutes sops-nix placeholders into the configuration;
4. writes a runtime file outside the Nix Store;
5. applies mode `0600`;
6. validates JSON syntax and sing-box semantics;
7. atomically exposes the new file at `~/.config/sing-box/config.json`.

Only secret formats safe for JSON string substitution are used. The generated file is parsed after rendering so any escaping error fails activation before the runtime configuration is replaced.

## New Mac Bootstrap

A completely new Mac uses:

```text
1. Clone the repository.
2. Restore the shared age private key at the standard macOS SOPS path.
3. Run ./bootstrap.sh.
4. Let sops-nix decrypt and render the sing-box configuration.
5. Import the validated runtime configuration into SFM.
```

`bootstrap.sh` and `rebuild.sh` will both target `darwinConfigurations.mac`.

The script interfaces become:

```text
./bootstrap.sh
./rebuild.sh
./rebuild.sh --update
```

The scripts must fail early with a clear path-specific message when the age private key is missing. They must not generate a replacement key because a new identity cannot decrypt the committed SOPS file.

## SFM Profile Synchronization

SFM supports local configuration profiles but stores profile content as application state rather than continuously watching `~/.config/sing-box/config.json`.

The synchronization policy is:

- all edits happen in the repository template and encrypted SOPS file;
- SFM profile content is derived from the rendered configuration;
- configuration is synchronized only after all validation succeeds;
- `rebuild.sh` does not start SFM automatically;
- direct long-lived edits in the SFM editor are prohibited.

During implementation, the official SFM file import behavior will be tested end to end. If SFM provides a stable file import mechanism, a user-invoked `sfm-sync` helper will use it. If no reliable automation is available, the documented workflow will require re-importing the validated file in SFM. The implementation must not write directly into SFM private application containers.

## Network Configuration

### Inbounds

The configuration has two inbounds:

#### `tun-in`

- type: TUN;
- IPv4 and IPv6 addresses;
- system stack;
- lifecycle controlled by SFM Network Extension;
- no separate CLI TUN instance.

Options managed or ignored by the Apple Network Extension will be minimized after testing against the official SFM feature matrix.

#### `mixed-in`

- type: mixed SOCKS/HTTP;
- listen address: `127.0.0.1`;
- listen port: `7777`;
- purpose: terminal diagnostics and explicit per-application proxying.

It must never listen on a LAN or public address.

### Physical Outbounds

The two servers expose:

- `sg-vless`: VLESS, REALITY, Vision, uTLS Chrome fingerprint;
- `sg-hy2`: Hysteria2, TLS, Salamander obfuscation;
- `us-vless`: VLESS, REALITY, Vision, uTLS Chrome fingerprint;
- `us-hy2`: Hysteria2, TLS, Salamander obfuscation.

The previous bandwidth hints are:

- Singapore Hysteria2: 45 Mbps up, 170 Mbps down;
- US Hysteria2: 32 Mbps up, 95 Mbps down.

Implementation will preserve them unless current sing-box guidance or testing shows that omission is safer.

### Selector Hierarchy

The primary selector is:

```text
proxy
├── auto
├── singapore
├── usa
├── sg-vless
├── sg-hy2
├── us-vless
└── us-hy2
```

Behavior:

- `proxy` defaults to `auto`;
- `auto` URL-tests all four physical outbounds;
- `singapore` URL-tests both Singapore protocols;
- `usa` URL-tests both US protocols;
- automatic changes do not interrupt existing connections;
- explicit manual changes may interrupt existing connections so the new selection takes effect immediately;
- the initial URL-test interval target is ten minutes to reduce battery and background traffic;
- no separate TCP or UDP selector is added without measured evidence.

## DNS Design

The DNS design uses FakeIP to prevent polluted answers from controlling proxied destinations.

### Behavior

- TUN hijacks ordinary DNS traffic.
- A and AAAA queries normally receive FakeIP answers.
- IPv4 and IPv6 FakeIP pools are enabled.
- Resolution and connection strategy prefers IPv4 but permits IPv6.
- FakeIP mappings are stored in the sing-box cache.
- proxy server hostnames are resolved by an inline hosts server with their fixed IP addresses, avoiding bootstrap recursion and pollution;
- local, `.local`, reverse lookup, private, and link-local names use local resolution;
- direct destinations use a mainland-compatible encrypted DNS resolver;
- proxied destinations preserve the domain through the proxy path and do not depend on a potentially polluted local answer.

The final configuration will use the structured DNS server format supported by sing-box 1.13.14 and accepted by the official Schema wherever the stable version and latest online Schema overlap.

## Routing Design

### Rule Set Source

The GFWList rule set is:

```text
https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/gfw.srs
```

It is a remote binary sing-box rule set with a 24-hour update interval. It is downloaded through a known working bootstrap proxy outbound. Cached rules remain usable when refresh fails.

### Priority

Routing rules are evaluated in this order:

1. protocol sniffing;
2. DNS hijacking;
3. proxy server endpoints, private IPs, and LAN traffic to `direct`;
4. `custom-reject`;
5. `custom-direct`;
6. `custom-proxy`;
7. OpenAI to `proxy`;
8. Claude to `proxy`;
9. Google Meet domains, official media IPs, and required UDP ports to `proxy`;
10. MetaCubeX GFWList to `proxy`;
11. unmatched traffic to `direct`.

### Custom Rules

Three inline rule sets live in the main configuration:

- `custom-reject`;
- `custom-direct`;
- `custom-proxy`.

They may contain domain, suffix, keyword, CIDR, port, and process rules. This preserves explicit user overrides without adding a second configuration source.

### Service Rules Retained

Only these service policies have sufficient evidence:

- OpenAI must use `proxy` because mainland China is not a supported access region, while both Singapore and the United States are supported.
- Claude must use `proxy` because Anthropic enforces supported-region policy using IP-derived location, while both proxy regions are supported.
- Google Meet domains, official media IP ranges, and required UDP ports must use `proxy` to preserve media connectivity. It is not fixed to Hysteria2 because there is no evidence that one proxy protocol is universally superior.

The following old policies are removed:

- Apple direct, because final routing is already direct;
- fixed Singapore routing for OpenAI, Claude, Paid, Monoova, and WorkOS;
- Hysteria2-only routing for WhatsApp, YouTube, and Meet;
- broad AWS and Cloudflare proxy rules;
- explicit proxy rules for GitHub, Homebrew, Figma, Slack, Stripe, Atlassian, Logitech, and Google Analytics.

Those services use GFWList and the default direct behavior unless a reproducible failure justifies a future custom rule.

## Dashboard and API

No Web Dashboard is configured.

No Clash API listener is configured.

SFM provides:

- start and stop controls;
- logs;
- selector groups;
- URL tests;
- manual node switching;
- runtime status.

This avoids exposing an unnecessary local API and avoids requiring the sing-box 1.14 alpha API service.

## Single-Instance Safety

Single-instance behavior is a hard requirement.

The implementation must ensure:

- SFM is the only runtime owner;
- no `sing-box run` process is started by scripts;
- no sing-box LaunchAgent or LaunchDaemon exists;
- there is one active sing-box Network Extension;
- there is one TUN owner;
- repeated SFM start actions do not create another core;
- stopping SFM restores system DNS and routes;
- configuration rebuilds do not start or restart SFM.

Preflight and acceptance checks will inspect processes, launchd services, listening ports, Network Extension state, TUN interfaces, and default routes without printing secrets.

## Failure Handling

Configuration generation is transactional:

1. verify the age identity;
2. decrypt SOPS data;
3. render a temporary configuration;
4. parse it as JSON;
5. run `sing-box check`;
6. atomically publish it only when all checks pass.

On failure:

- activation returns non-zero;
- the previous valid runtime configuration remains available;
- SFM is not started, stopped, or modified;
- no partial plaintext file is retained;
- secret values are not printed.

Remote rule-set refresh failure uses the cached rule set. Initial startup requires a working physical proxy outbound so the first GFWList download can complete.

## Validation Plan

### Static Validation

- `nix flake check`;
- build `darwinConfigurations.mac.system`;
- run `shellcheck` on changed shell scripts;
- validate the template structure against the official sing-box JSON Schema;
- parse the rendered configuration with `jq`;
- validate the rendered configuration with `sing-box check`;
- scan pending and committed files for the age private key and known plaintext secrets.

The installed stable sing-box check is authoritative if the latest online Schema contains fields from an unreleased version.

### End-to-End Validation

1. Reproduce the current user flow by importing the generated configuration into SFM.
2. Start SFM and confirm exactly one Network Extension instance.
3. Confirm there is no CLI sing-box process or launchd service.
4. Confirm TUN captures IPv4 and IPv6.
5. Confirm ordinary A and AAAA queries receive addresses from the expected FakeIP ranges.
6. Confirm LAN and `.local` access continues to work.
7. Confirm a GFWList domain uses the selected proxy.
8. Confirm an unmatched domain remains direct.
9. Confirm OpenAI and Claude use `proxy`.
10. Confirm Google Meet TCP and UDP connectivity.
11. Test all four physical outbounds independently.
12. Confirm `auto`, `singapore`, and `usa` URL tests work.
13. Switch country and protocol through SFM and confirm the effective egress changes.
14. Stop SFM and confirm DNS, routes, and TUN state are restored.
15. Repeat start, stop, import, and switching operations and confirm no duplicate instance appears.

## Migration and Cleanup

The old `/Users/rich/Downloads/config.json` is mode `0644` and contains complete plaintext credentials.

Implementation will:

1. extract required values locally without displaying them;
2. create the encrypted SOPS data;
3. verify that SOPS can decrypt it with the shared age identity;
4. validate and run the new configuration;
5. request explicit user permission before deleting the old plaintext file.

The old Clash API secret is treated as compromised and is not reused. Since the new design has no Clash API, no replacement API secret is needed.

## Out of Scope

- running a separate sing-box CLI service;
- Web Dashboard;
- Clash API;
- third-party GUI or TUI clients;
- automatic subscription conversion;
- per-application routing without a demonstrated need;
- automatic deletion of the old plaintext configuration;
- separate laptop and desktop Darwin configurations.

## Acceptance Criteria

The design is complete when:

- both Macs build the same `darwinConfigurations.mac`;
- the encrypted secrets are safely committed and decrypt with the shared age key;
- the final configuration is schema-assisted, valid JSON, and accepted by sing-box 1.13.14;
- SFM is installed declaratively and runs the configuration through one Network Extension instance;
- FakeIP, dual stack, GFWList routing, custom rules, and service exceptions work as designed;
- all four nodes can be selected and `auto` chooses among them;
- unmatched traffic is direct;
- stopping SFM restores the system network state;
- no duplicate sing-box runtime or persistent CLI service exists.
