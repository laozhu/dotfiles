{ lib, user, ... }:

{
  # Determinate 已经管理了 Nix daemon，关闭 nix-darwin 的管理防止冲突
  nix.enable = false;
  
  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # Apple Silicon

  # 临时补齐 nixpkgs 尚未收录的稳定补丁版；上游追上后自动使用上游包。
  nixpkgs.overlays = [
    (final: prev: {
      sing-box = if lib.versionOlder prev.sing-box.version "1.14.2" then
        prev.sing-box.overrideAttrs (finalAttrs: _: {
          version = "1.14.2";
          src = final.fetchFromGitHub {
            owner = "SagerNet";
            repo = "sing-box";
            tag = "v${finalAttrs.version}";
            hash = "sha256-KoJj5nn0d7uxs5x4arG1p3KGkDmaFAJKiVJ5M5vYxcU=";
          };
          vendorHash = "sha256-DJNYQeCgAouLvpA8caZ0ILi9RYV82wteV6tR3gj+sfI=";
        })
      else prev.sing-box;

      pnpm = if lib.versionOlder prev.pnpm.version "12.9.1" then
        prev.pnpm.override {
          version = "12.9.1";
          srcHash = "sha256-inKhKFbI0M1exWL3jDhBmd+VnSwnGdxYOM4LTvs2Vuw=";
          cargoHash = "sha256-NGefDu4dGMC2RGrTPeYBuRrG+Gb8jnx9+SbyK8WPd9E=";
        }
      else prev.pnpm;

      uv = if lib.versionOlder prev.uv.version "0.12.23" then
        prev.uv.overrideAttrs (finalAttrs: _: {
          version = "0.12.23";
          src = final.fetchFromGitHub {
            owner = "astral-sh";
            repo = "uv";
            tag = finalAttrs.version;
            hash = "sha256-U/LhX0XkUgbAXZZeLTBGF2nX2yzFb5zpiScCBD62pk4=";
          };
          cargoDeps = final.rustPlatform.fetchCargoVendor {
            inherit (finalAttrs) src;
            hash = "sha256-mzdpBXd8unvodVs4hk5Qw9pNhiAo5BaJjlNeqzop1GE=";
          };
        })
      else prev.uv;
    })
  ];

  system.primaryUser = user;
  system.stateVersion = 6;

  # 设置系统时区，匹配国内环境
  time.timeZone = "Asia/Shanghai";

  users.users.${user} = {
    home = "/Users/${user}";
  };

  system.defaults = {
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
    ];

    # 🛑 命令行及 CLI Agent 工具已全部交给 Nix 接管，此处清空
    brews = [];

    # 只保留纯 GUI 桌面级应用
    casks = [
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
