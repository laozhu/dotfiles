#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
for profile in home work; do
  nix eval --json "path:$repo_dir#darwinConfigurations.$profile.config" --apply '
    c: let home = c.home-manager.users.${c.system.primaryUser}; in {
      casks = map (x: x.name) c.homebrew.casks;
      brews = map (x: x.name) c.homebrew.brews;
      cleanup = c.homebrew.onActivation.cleanup;
      packages = map (x: x.pname or x.name) home.home.packages;
      lfs = home.programs.git.lfs.enable;
      direnv = home.programs.direnv.enable;
      javaHome = home.home.sessionVariables.JAVA_HOME;
      paths = home.home.sessionPath;
      serviceNames = builtins.attrNames c.launchd.daemons
        ++ builtins.attrNames c.launchd.agents
        ++ builtins.attrNames home.launchd.agents;
    }
  ' | jq -e --arg profile "$profile" '
    .cleanup == "zap" and .lfs and .direnv and
    ([.serviceNames[] | select(test("sing[-_.]?box"; "i"))] | length == 0) and
    (.brews | index("sing-box") == null) and
    .javaHome == "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home" and
    (.paths | index("/opt/homebrew/opt/python/libexec/bin") != null) and
    (["python", "openjdk", "gradle", "k1low/tap/mo"] - .brews | length == 0) and
    (["bitwarden", "wechat", "wechatwebdevtools", "orbstack", "imageoptim", "keka"] - .casks | length == 0) and
    (["rustc", "cargo", "tig", "yq-go", "caddy", "ffmpeg"] - .packages | length == 0) and
    (.casks | index("magnet") == null) and
    (if $profile == "home" then
      (["steam", "uu-booster", "logitech-g-hub", "tencent-meeting"] - .casks | length == 0) and
      ([.casks[] | select(. == "slack" or . == "nordpass" or . == "granola" or . == "loom" or . == "slack-cli")] | length == 0) and
      ([.brews[] | select(. == "awscli" or . == "aws-sam-cli" or . == "temporal" or . == "nordpass/tap/np" or . == "atlassian/acli/acli")] | length == 0)
    else
      (["slack", "nordpass", "granola", "loom", "slack-cli"] - .casks | length == 0) and
      (["awscli", "aws-sam-cli", "temporal", "nordpass/tap/np", "atlassian/acli/acli"] - .brews | length == 0) and
      ([.casks[] | select(. == "steam" or . == "uu-booster" or . == "logitech-g-hub" or . == "tencent-meeting")] | length == 0)
    end)
  ' >/dev/null
done
