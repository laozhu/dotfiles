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

    sops-nix = {
      url = "github:Mic92/sops-nix";
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
    orca-tap = {
      url = "github:stablyai/homebrew-orca";
      flake = false;
    };
  };

  outputs = inputs@{ self, darwin, nixpkgs, home-manager, llm-agents, nix-homebrew, sops-nix, ... }:
    let
      user = "rich";
      # M4 芯片架构统一为 aarch64-darwin
      system = "aarch64-darwin"; 
      
      # 💡 提取共享模块：笔记本和台式机共用的所有配置
      sharedModules = [
        ./configuration.nix
        ./sing-box.nix

        sops-nix.darwinModules.sops

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
              "stablyai/orca" = inputs.orca-tap;
            };
            mutableTaps = false;
          };
        }
      ];
    in
    {
      darwinConfigurations.mac = darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit user inputs; };
        modules = sharedModules;
      };
    };
}
