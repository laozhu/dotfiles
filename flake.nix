{
  description = "Nix-darwin configuration for macOS";

  inputs = {
    # 核心包集合
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    
    # Nix-darwin
    darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 🤖 引入专门管理 AI Agents 的 Flake 源 (每日 CI 自动同步构建)
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix-Homebrew 官方 Taps and Casks
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs = inputs@{ self, darwin, nixpkgs, home-manager, llm-agents, nix-homebrew, ... }:
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
          # 传递 inputs 给 home.nix，便于直接引用 inputs.llm-agents
          home-manager.extraSpecialArgs = { inherit user inputs; };
          home-manager.users.${user} = import ./home.nix;
        }

        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            user = user;
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
