{ lib, user, ... }:

let
  preferredLanguages = [ "en-SG" "zh-SG" ];
  timeZone = "Asia/Singapore";
in
{
  # Determinate 已经管理了 Nix daemon，关闭 nix-darwin 的管理防止冲突
  nix.enable = false;
  
  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # Apple Silicon

  # These tools always use pinned official macOS binaries, never source builds.
  nixpkgs.overlays = [
    (final: prev:
      let binaries = prev.callPackage ./macos-binaries.nix { }; in {
        inherit (binaries) pnpm uv sing-box bws herdr kimi-code pi;
      })
  ];

  system.primaryUser = user;
  system.stateVersion = 6;

  # 设置系统时区为新加坡
  time.timeZone = timeZone;

  users.users.${user} = {
    home = "/Users/${user}";
  };

  system.defaults = {
    # Safari 跟随系统首选语言；Chrome 通过策略使用相同的语言顺序。
    CustomUserPreferences.".GlobalPreferences".AppleLanguages = preferredLanguages;
    CustomUserPreferences.".GlobalPreferences".AppleLocale = "en_SG";
    CustomUserPreferences."com.google.Chrome".ForcedLanguages = preferredLanguages;

    NSGlobalDomain = {
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
      show-recents = false;            # 隐藏 Dock 右侧的最近使用
      mru-spaces = false;              # 🛑 核心痛点：关闭“根据最近使用情况自动重新排列空间”
    };

    finder = {
      FXPreferredViewStyle = "Nlsv";   # 默认列表视图
      CreateDesktop = false;           # 隐藏桌面图标，保持专注
    };

    trackpad = {
      Clicking = true;                 # 轻触点击
    };
  };

  # 注入南京大学 (NJU) 的 API 与 Bottles 镜像
  environment.variables = {
    HOMEBREW_API_DOMAIN = "https://mirror.nju.edu.cn/homebrew-bottles/api";
    HOMEBREW_BOTTLE_DOMAIN = "https://mirror.nju.edu.cn/homebrew-bottles";
    HOMEBREW_BREW_GIT_REMOTE = "https://mirror.nju.edu.cn/git/homebrew/brew.git";
    HOMEBREW_CORE_GIT_REMOTE = "https://mirror.nju.edu.cn/git/homebrew/homebrew-core.git";
  };

  homebrew = {
    enable = true;

    # 🔄 支持自动化清洗、更新及底层应用升级
    onActivation = {
      cleanup = "zap";       # 移除所有未在列表中声明的包
      autoUpdate = true;     # 构建前自动更新 Homebrew 仓库
      upgrade = true;        # 👈 自动将所有 Casks 升级到最新版本
      extraFlags = [ "--force" ];
    };

    # 显式声明你需要这些 Taps
    taps = [
      "homebrew/core"
      "homebrew/cask"
      "stablyai/orca"
      "daipeihust/tap"
    ];

    # 常规 CLI 由 Nix 管理；im-select 使用上游 tap，Codex 使用官方 cask。
    brews = [ "daipeihust/tap/im-select" ];

    # 桌面应用及使用官方 macOS 二进制的 Codex CLI
    casks = [
      "codex"
      "antigravity-ide"
      "bitwarden"
      "sfm"
      "chatgpt"
      "claude"
      "google-chrome"
      "google-gemini"
      "visual-studio-code"
      "wechat"
      "wechatwebdevtools"
      "wezterm"
      "orbstack"
      "logitech-g-hub"
      "steam"
      "uu-booster"
      "stablyai/orca/orca"
    ];
  };
}
