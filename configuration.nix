{ user, ... }:

{
  # Determinate 已经管理了 Nix daemon，关闭 nix-darwin 的管理防止冲突
  nix.enable = false;
  
  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # Apple Silicon

  system.primaryUser = user;
  system.stateVersion = 6;

  # 设置系统时区，匹配国内环境
  time.timeZone = "Asia/Shanghai";

  users.users.${user} = {
    home = "/Users/${user}";
  };

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      AppleShowAllExtensions = true;
      KeyRepeat = 2;          # 极速按键重复 (开发者必需)
      InitialKeyRepeat = 15;  # 缩短长按触发重复的延迟

      # 🛑 开发者防坑必备：关闭 macOS 各类“自作聪明”的文本替换
      NSAutomaticCapitalizationEnabled = false;      # 关闭自动首字母大写
      NSAutomaticDashSubstitutionEnabled = false;    # 关闭自动双横杠替换为长破折号（防止 --help 报错）
      NSAutomaticPeriodSubstitutionEnabled = false;  # 关闭双击空格自动输入句号
      NSAutomaticQuoteSubstitutionEnabled = false;   # 关闭智能引号（防止破坏 JSON/代码结构）
      NSAutomaticSpellingCorrectionEnabled = false;  # 关闭自动拼写纠正
    };

    dock = {
      autohide = true;
      show-recents = false;            # 隐藏 Dock 右侧的最近使用
      mru-spaces = false;              # 🛑 核心痛点：关闭“根据最近使用情况自动重新排列空间”
    };

    finder = {
      FXPreferredViewStyle = "Nlsv";   # 默认列表视图
      CreateDesktop = false;           # 隐藏桌面图标，保持专注
    };

    # 🔧 修复：原本写成了 trackpad { Clicking = true; } 导致语法报错
    trackpad.Clicking = true;          # 轻触点击
  };

  # 注入 Homebrew 镜像环境变量，确保下载加速
  environment.variables = {
    HOMEBREW_API_DOMAIN = "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api";
    HOMEBREW_BOTTLE_DOMAIN = "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles";
    HOMEBREW_BREW_GIT_REMOTE = "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git";
    HOMEBREW_CORE_GIT_REMOTE = "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git";
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # 无情模式：移除所有未在列表中声明的包
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];

    # 💡 优化：对于国内用户，关闭 Cask 应用的 macOS 隔离机制，防止打开应用时提示损坏
    caskArgs.no_quarantine = true;

    brews = [];

    casks = [
      "bitwarden"
      "google-chrome"
      "wezterm"
    ];
  };
}
