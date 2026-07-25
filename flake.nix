{
  description = "Nix-darwin configuration for macOS";

  inputs = {
    # 核心包集合 (使用稳定版或 unstable 均可，这里保留 unstable)
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    
    # Nix-darwin (修复了拼写错误)
    darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix-Homebrew 及国内清华源 Taps
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    homebrew-core = {
      url = "git+https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git";
      flake = false;
    };
    homebrew-cask = {
      url = "git+https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-cask.git";
      flake = false;
    };
  };

  outputs = inputs@{ self, darwin, nixpkgs, home-manager, nix-homebrew, ... }:
    let
      user = "rich";
      # M4 芯片架构统一为 aarch64-darwin
      system = "aarch64-darwin"; 
      
      # 💡 提取共享模块：笔记本和台式机共用的所有配置
      sharedModules = [
        ./configuration.nix

        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit user; };
          home-manager.users.${user} = import ./home.nix;
        }

        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            user = user;
            # 注入清华源的 Taps
            taps = {
              "homebrew/homebrew-core" = inputs.homebrew-core;
              "homebrew/homebrew-cask" = inputs.homebrew-cask;
            };
            mutableTaps = false;
          };
        }
      ];
    in
    {
      # 💻 笔记本电脑配置
      darwinConfigurations."mac-laptop" = darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit user inputs; };
        modules = sharedModules;
      };

      # 🖥️ 台式机电脑配置 (复用完全相同的模块)
      darwinConfigurations."mac-desktop" = darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit user inputs; };
        modules = sharedModules;
      };
    };
}
