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
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
      inputs.brew-src.follows = "brew-src";
    };
    # Update Brew together with the formulae, rather than inheriting an older release.
    brew-src = {
      url = "github:Homebrew/brew";
      flake = false;
    };
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
    im-select-tap = {
      url = "github:daipeihust/homebrew-tap";
      flake = false;
    };
    mo-tap = {
      url = "github:k1LoW/homebrew-tap";
      flake = false;
    };
    atlassian-tap = {
      url = "github:atlassian/homebrew-acli";
      flake = false;
    };
    temporal-tap = {
      url = "github:temporalio/homebrew-brew";
      flake = false;
    };
    nordpass-tap = {
      # This server uses dumb HTTP Git and cannot serve shallow clones.
      url = "git+https://downloads.npass.app/cli/homebrew-tap.git?shallow=0";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      darwin,
      nixpkgs,
      home-manager,
      llm-agents,
      nix-homebrew,
      sops-nix,
      ...
    }:
    let
      user = "rich";
      # M4 芯片架构统一为 aarch64-darwin
      system = "aarch64-darwin";

      # Keep the official tap pinned by flake.lock without Determinate's shallow optimization.
      nordpassTap = import ./lib/non-shallow-git.nix (
        (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nordpass-tap.locked
      );

      # 💡 提取共享模块：笔记本和台式机共用的所有配置
      sharedModules = profile: [
        ./configuration.nix
        ./sing-box.nix

        sops-nix.darwinModules.sops

        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          # 传递 inputs 给 home.nix，便于直接引用 inputs.llm-agents
          home-manager.extraSpecialArgs = { inherit user inputs profile; };
          home-manager.users.${user} = import ./home.nix;
        }

        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            user = user;
            # This input follows Brew's main branch; do not label it with nix-homebrew's release.
            package = inputs.brew-src // {
              name = "brew-${inputs.brew-src.shortRev}";
            };
            taps = {
              "homebrew/homebrew-core" = inputs.homebrew-core;
              "homebrew/homebrew-cask" = inputs.homebrew-cask;
              "stablyai/homebrew-orca" = inputs.orca-tap;
              "daipeihust/homebrew-tap" = inputs.im-select-tap;
              "k1low/homebrew-tap" = inputs.mo-tap;
            }
            // nixpkgs.lib.optionalAttrs (profile == "work") {
              "atlassian/homebrew-acli" = inputs.atlassian-tap;
              "temporalio/homebrew-brew" = inputs.temporal-tap;
              "nordpass/homebrew-tap" = nordpassTap;
            };
            mutableTaps = false;
          };
        }
      ];
      mkMac =
        profile:
        darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit user inputs profile; };
          modules = sharedModules profile;
        };
    in
    {
      darwinConfigurations = {
        home = mkMac "home";
        work = mkMac "work";
        # Compatibility for existing package references; scripts select explicitly.
        mac = self.darwinConfigurations.home;
      };
    };
}
