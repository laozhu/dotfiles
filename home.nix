{
  config,
  lib,
  pkgs,
  user,
  inputs,
  profile,
  ...
}:

let
  software = import ./software.nix { inherit lib profile; };
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  githubAccount =
    if profile == "work" then
      {
        login = "ritchie-paid";
        configDir = "gh";
      }
    else
      {
        login = "laozhu";
        configDir = "gh-laozhu";
      };
  githubEnvironment = ''
    export GH_CONFIG_DIR="$HOME/.config/${githubAccount.configDir}"
    export GITHUB_ACTOR=${githubAccount.login}
    unset GH_TOKEN GITHUB_TOKEN
  ''
  + lib.optionalString (profile == "work") ''
    case "$PWD/" in
      "$HOME/Developer/laozhu/"* | "$HOME/Developer/beebat-dev/"*)
        export GH_CONFIG_DIR="$HOME/.config/gh-laozhu"
        export GITHUB_ACTOR=laozhu
        ;;
    esac
  '';
  githubToken = builtins.readFile ./scripts/github-token.sh;
  # Work tooling requires JDK 21; the latest OpenJDK stays installed for Gradle and home.
  javaPrefix = "/opt/homebrew/opt/${if profile == "work" then "openjdk@21" else "openjdk"}";

  # 用于 AI 智能体的统一全局上下文规则
  sharedAgentContext = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  claudeContext = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/CLAUDE.md";

  # 提取当前系统的 llm-agents 包集合
  llmPkgs = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  fileSearch = "${pkgs.fd}/bin/fd --type f --strip-cwd-prefix --hidden --exclude .git";
in
{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "26.05";

  home.packages = software.packages pkgs llmPkgs;

  # Shared by bootstrap and rebuild; profiles and credentials remain writable/local.
  # Installs need the network, so a failure warns instead of aborting the whole switch.
  home.activation.dshPlugins = lib.hm.dag.entryAfter [ "linkGeneration" ] (
    lib.concatMapStringsSep "\n" (plugin: ''
      run env PATH="${
        lib.makeBinPath [
          pkgs.nodejs_26
          pkgs.pnpm
          pkgs.jq
          llmPkgs.dsh
        ]
      }:$PATH" \
        ${pkgs.bash}/bin/bash ${./scripts/sync-dsh-plugin.sh} \
        ${
          lib.escapeShellArgs [
            plugin.profile
            plugin.package
            plugin.version
          ]
        } \
        || warnEcho "DSH plugin ${plugin.package}@${plugin.version} was not installed; rerun rebuild once the network works."
    '') software.dshPlugins
  );

  # Homebrew Python and Java must precede Apple's CLT Python and launcher stubs.
  home.sessionPath = [
    "/opt/homebrew/opt/python/libexec/bin"
    "${javaPrefix}/bin"
    "/opt/homebrew/bin"
    "${config.home.profileDirectory}/bin"
    "/run/current-system/sw/bin"
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
  ];
  home.sessionVariables.JAVA_HOME = "${javaPrefix}/libexec/openjdk.jdk/Contents/Home";
  programs.uv = {
    enable = true;
    package = null; # The pinned binary is already declared in software.json.
    settings.python-preference = "system";
  };
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";
  home.sessionVariables.GH_CONFIG_DIR = "${config.home.homeDirectory}/.config/${githubAccount.configDir}";
  home.sessionVariables.GITHUB_ACTOR = githubAccount.login;

  # 启用并完全接管 Git
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      core.editor = "nvim";
      init.defaultBranch = "main";
      user.name = "Ritchie Zhu";
      push.autoSetupRemote = true;
      fetch.prune = true;
      merge.conflictStyle = "zdiff3";
      pull.ff = "only";
      rerere.enabled = true;
      diff.colorMoved = "zebra";
    };
  };

  # 启用 fzf 及其 Zsh Shell 集成
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = fileSearch;
    fileWidget.command = fileSearch;
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # 优化历史记录容量，提升 autosuggestion 的联想效果
    history = {
      size = 10000;
      save = 10000;
      path = "${config.home.homeDirectory}/.zsh_history";
      ignoreDups = true;
      share = true;
    };

    initContent = ''
      bindkey '^f' autosuggest-accept
      ${githubEnvironment}
      ${githubToken}
      # Apply after macOS path_helper and Home Manager's Nix profile setup.
      export PATH="/opt/homebrew/opt/python/libexec/bin:${javaPrefix}/bin:/opt/homebrew/bin:$PATH"
    '';

    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Shared activation makes bootstrap and rebuild preserve local Claude settings.
  # Invalid local JSON is left untouched and only skips the status line updates.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run env PATH="${lib.makeBinPath [ pkgs.jq ]}:$PATH" \
      ${pkgs.bash}/bin/bash ${./scripts/sync-claude-statusline.sh} \
      "$HOME/.claude/settings.json" ${./home/.claude/settings.json} \
      "${pkgs.ccometixline}/bin/ccline" \
      || warnEcho "Claude statusLine not updated; fix ~/.claude/settings.json and rerun rebuild."
  '';

  # Merge the managed Codex footer status line; Codex keeps writing the rest of the file.
  home.activation.codexStatusLine = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run env PATH="${lib.makeBinPath [ pkgs.yq-go ]}:$PATH" \
      ${pkgs.bash}/bin/bash ${./scripts/sync-codex-statusline.sh} \
      "$HOME/.codex/config.toml" ${./home/.codex/tui.toml} \
      || warnEcho "Codex status line not updated; fix ~/.codex/config.toml and rerun rebuild."
  '';

  # Convert a Pi settings link left by older generations before linkGeneration removes it.
  home.activation.piSettingsMigration =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        if [ -L "$HOME/.pi/agent/settings.json" ]; then
          run ${pkgs.bash}/bin/bash ${./scripts/init-pi-settings.sh} \
            "$HOME/.pi/agent/settings.json" ${./home/.pi/agent/settings.json}
        fi
      '';

  # 统一文件映射 (使用软链接便于实时修改)
  home.file = {
    ".gradle/gradle.properties".text = ''
      org.gradle.caching=true
    '';

    # Public identity configuration only; private keys and gh OAuth stay local.
    # Keep the legacy out-of-store sources intact until old generations are replaced.
    ".gitconfig".text =
      builtins.readFile ./home/.config/git/common.inc
      + ''
        [include]
          path = ~/.config/git/${githubAccount.login}.inc
      ''
      + lib.optionalString (profile == "work") ''
        [includeIf "gitdir:~/Developer/laozhu/"]
          path = ~/.config/git/laozhu.inc
        [includeIf "gitdir:~/Developer/beebat-dev/"]
          path = ~/.config/git/laozhu.inc
      '';
    ".config/git/ritchie-paid.inc" = lib.mkIf (profile == "work") {
      source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/git/ritchie-paid.inc";
    };
    ".ssh/config".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.ssh/config";
    ".config/git/laozhu.inc".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/git/laozhu.inc";
    ".config/direnv/direnvrc".text =
      githubEnvironment
      + lib.optionalString (profile == "work") (
        builtins.readFile ./home/.config/direnv/work-secrets.envrc
      )
      + githubToken;
    "Developer/paid-inc/.envrc".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/direnv/github.envrc";
    "Developer/laozhu/.envrc".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/direnv/github.envrc";
    "Developer/beebat-dev/.envrc".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/direnv/github.envrc";

    # 基础应用配置
    ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
    ".config/nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
    ".config/herdr".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
    ".config/sing-box/config.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/sing-box/config.json";

    # 只接管仓库维护的 Pi 资源，凭证、会话和缓存继续保留在本机
    ".pi/agent/themes/rose-pine-moon.json".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/themes/rose-pine-moon.json";
    ".pi/agent/extensions/terminal-status-title.js".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/extensions/terminal-status-title.js";

    ".claude/ccline/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/ccline/config.toml";

    # AI Agents 配置文件注入
    ".claude/CLAUDE.md".source = claudeContext;
    ".claude/AGENTS.md".source = sharedAgentContext;
    ".pi/agent/AGENTS.md".source = sharedAgentContext;
    ".codex/AGENTS.md".source = sharedAgentContext;
  };
}
