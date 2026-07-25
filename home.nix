{ config, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  
  # 用于 AI 智能体的统一全局上下文规则
  sharedAgentContext = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
in
{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  
  # Search on https://search.nixos.org/packages
  home.packages = with pkgs; [
    # --- 高频使用的 CLI 工具 ---
    ripgrep   # Telescope live_grep 必需
    fd        # Telescope find_files 必需
    fzf       # 模糊搜索工具
    jq        # 命令行 JSON 处理
    lazygit
    neovim
    herdr     # Agent 多开工具
    nerd-fonts.hack

    # -----------------------------------------------------------
    # 🛠️ Neovim 核心底层依赖 (Treesitter & Mason 必需)
    # -----------------------------------------------------------
    gnumake   # 编译 Treesitter 语法解析器的必备构建工具
    gcc       # C 编译器，Treesitter 强依赖
    unzip     # Mason 下载并解压 LSP 的必备工具
    curl      # Mason 的底层网络工具
    wget      
    
    # -----------------------------------------------------------
    # 📦 运行时依赖
    # -----------------------------------------------------------
    nodejs_26
    bun

  ];
  
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";

  # 启用并完全接管 Git
  programs.git = {
    enable = true;
    userName = "Ritchie Zhu";
    userEmail = "laozhu.me@gmail.com";
    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "nvim";
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

    initExtra = ''
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

    # AI Agents 配置文件注入
    ".claude/settings.json".source      = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
    ".claude/CLAUDE.md".source          = sharedAgentContext;
    ".codex/AGENTS.md".source           = sharedAgentContext;
    ".config/opencode/AGENTS.md".source = sharedAgentContext;
  };
}
