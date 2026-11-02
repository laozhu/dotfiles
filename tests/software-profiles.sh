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
      dshPlugins = home.home.activation.dshPlugins.data;
      javaHome = home.home.sessionVariables.JAVA_HOME;
      paths = home.home.sessionPath;
      profileBin = "${home.home.profileDirectory}/bin";
      pythonPreference = home.programs.uv.settings.python-preference or null;
      gradleProperties = home.home.file.".gradle/gradle.properties".text or "";
      fzfCommand = home.programs.fzf.defaultCommand;
      fzfFileCommand = home.programs.fzf.fileWidget.command;
      serviceNames = builtins.attrNames c.launchd.daemons
        ++ builtins.attrNames c.launchd.agents
        ++ builtins.attrNames home.launchd.agents;
    }
  ' | jq -e --arg profile "$profile" '
    .cleanup == "zap" and .lfs and .direnv and
    (.dshPlugins | contains("sync-dsh-plugin.sh") and contains("tui") and contains("@deepseek-harness-tui/dsh-tui") and contains("0.18.0")) and
    ([.serviceNames[] | select(test("sing[-_.]?box"; "i"))] | length == 0) and
    (.brews | index("sing-box") == null) and
    .javaHome == "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home" and
    (.paths | index("/opt/homebrew/opt/python/libexec/bin") != null) and
    .pythonPreference == "system" and
    (.gradleProperties | contains("org.gradle.caching=true")) and
    .fzfCommand != null and .fzfCommand == .fzfFileCommand and
    (.paths as $paths | .profileBin as $profileBin |
      ($paths | index("$HOME/.local/bin")) as $local |
      ($paths | index("$HOME/.cargo/bin")) as $cargo |
      $local != null and $cargo != null and
      ($paths | index($profileBin)) < $local and
      ($paths | index($profileBin)) < $cargo and
      ($paths | index("/opt/homebrew/bin")) < $local and
      ($paths | index("/opt/homebrew/bin")) < $cargo) and
    (["python", "openjdk", "gradle", "k1low/tap/mo"] - .brews | length == 0) and
    (["bitwarden", "wechat", "wechatwebdevtools", "orbstack", "imageoptim", "keka", "deepseek-harness"] - .casks | length == 0) and
    (["rustc", "cargo", "tig", "yq-go", "caddy", "ffmpeg", "dsh"] - .packages | length == 0) and
    (.casks | index("magnet") == null) and
    (if $profile == "home" then
      (["steam", "uu-booster", "logitech-g-hub", "tencent-meeting"] - .casks | length == 0) and
      ([.casks[] | select(. == "slack" or . == "nordpass" or . == "granola" or . == "loom" or . == "slack-cli")] | length == 0) and
      ([.brews[] | select(. == "awscli" or . == "aws-sam-cli" or . == "temporal" or . == "temporalio/brew/tcld" or . == "nordpass/tap/np" or . == "atlassian/acli/acli")] | length == 0) and
      (.packages | index("qpdf") == null)
    else
      (["slack", "nordpass", "granola", "loom", "slack-cli"] - .casks | length == 0) and
      (["awscli", "aws-sam-cli", "temporal", "temporalio/brew/tcld", "nordpass/tap/np", "atlassian/acli/acli"] - .brews | length == 0) and
      (["qpdf"] - .packages | length == 0) and
      ([.casks[] | select(. == "steam" or . == "uu-booster" or . == "logitech-g-hub" or . == "tencent-meeting")] | length == 0)
    end)
  ' >/dev/null
done

# Exercise the configured file source, including dotfiles and Git ignore rules.
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
git -C "$fixture" init -q
mkdir -p "$fixture/.hidden" "$fixture/ignored"
printf 'ignored/\n' >"$fixture/.gitignore"
touch "$fixture/visible.txt" "$fixture/.hidden/visible.txt" "$fixture/ignored/skipped.txt"
primary_user="$(nix eval --raw "$repo_dir#darwinConfigurations.home.config.system.primaryUser")"
file_search="$(nix eval --raw "$repo_dir#darwinConfigurations.home.config.home-manager.users.$primary_user.programs.fzf.defaultCommand")"
nix build --no-link "$repo_dir#darwinConfigurations.home.pkgs.fd"
files="$(cd "$fixture" && bash -c "$file_search")"
grep -Fxq 'visible.txt' <<<"$files"
grep -Fxq '.hidden/visible.txt' <<<"$files"
if grep -Eq '(^\.git/|^ignored/)' <<<"$files"; then
  echo 'fzf file source included Git internals or ignored files' >&2
  exit 1
fi
