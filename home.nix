{ config, pkgs, user, inputs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  
  # 用于 AI 智能体的统一全局上下文规则
  sharedAgentContext = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  claudeContext = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/CLAUDE.md";

  # 提取当前系统的 llm-agents 包集合
  llmPkgs = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "26.05";
  
  # Search on https://search.nixos.org/packages
  home.packages = [
    # --- 高频使用的常规 CLI 工具 ---
    pkgs.ripgrep          # Telescope live_grep 必需
    pkgs.fd               # Telescope find_files 必需
    pkgs.fzf              # 模糊搜索工具
    pkgs.jq               # 命令行 JSON 处理
    pkgs.lazygit
    pkgs.neovim
    pkgs.github-cli       # GitHub 命令行工具
    pkgs.nerd-fonts.hack
    pkgs.age
    pkgs.bitwarden-cli
    pkgs.sops
    pkgs.sing-box

    # -----------------------------------------------------------
    # 🛠️ Neovim 核心底层依赖 (Treesitter & Mason 必需)
    # -----------------------------------------------------------
    pkgs.gnumake          # 编译 Treesitter 语法解析器的必备构建工具
    pkgs.gcc              # C 编译器，Treesitter 强依赖
    pkgs.unzip            # Mason 下载并解压 LSP 的必备工具
    pkgs.curl             # Mason 的底层网络工具
    pkgs.wget
    
    # -----------------------------------------------------------
    # 📦 运行时依赖
    # -----------------------------------------------------------
    pkgs.nodejs_26
    pkgs.pnpm
    pkgs.bun
    pkgs.uv
    pkgs.bws

    # -----------------------------------------------------------
    # 🤖 AI TUI Agents & 多开工具 (通过 llm-agents.nix 统一声明式管理)
    # -----------------------------------------------------------
    llmPkgs.herdr
    llmPkgs.claude-code
    llmPkgs.codex
    llmPkgs.antigravity-cli
    llmPkgs.kimi-code
    llmPkgs.pi
  ];
  
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";

  # 启用并完全接管 Git
  programs.git = {
    enable = true;
    settings = {
      core.editor = "nvim";
      init.defaultBranch = "main";
      user.email = "laozhu.me@gmail.com";
      user.name = "Ritchie Zhu";
    };
  };

  # 启用 fzf 及其 Zsh Shell 集成
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
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

  # 统一文件映射 (使用软链接便于实时修改)
  home.file = {
    # 基础应用配置
    ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
    ".config/nvim".source    = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
    ".config/herdr".source   = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
    ".config/sing-box/config.json".source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.local/state/sing-box/config.json";

    # 只接管仓库维护的 Pi 资源，凭证、会话和缓存继续保留在本机
    ".pi/agent/themes/rose-pine-moon.json".source = config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/home/.pi/agent/themes/rose-pine-moon.json";
    ".pi/agent/extensions/terminal-status-title.js".source = config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/home/.pi/agent/extensions/terminal-status-title.js";
    ".pi/agent/settings.json".source = config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/home/.pi/agent/settings.json";

    # AI Agents 配置文件注入
    ".claude/settings.json".source      = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
    ".claude/CLAUDE.md".source          = claudeContext;
    ".claude/AGENTS.md".source          = sharedAgentContext;
    ".pi/agent/AGENTS.md".source         = sharedAgentContext;
    ".codex/AGENTS.md".source           = sharedAgentContext;
    ".config/opencode/AGENTS.md".source = sharedAgentContext;
  };
}
