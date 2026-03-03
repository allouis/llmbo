{
  description = "LLM agent machines (home-manager and NixOS configurations)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jj-sync = {
      url = "git+ssh://git@github.com/allouis/jj-sync";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-config = {
      url = "git+ssh://git@github.com/allouis/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, disko, llm-agents, jj-sync, nix-config, ... }:
    let
      # Home-manager configuration (preserves existing OS)
      mkHome = { system, useDocker ? false }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          llmPkgs = llm-agents.packages.${system};
          jjSyncPkg = jj-sync.packages.${system}.default;
          # Use environment variables (requires --impure flag)
          username = builtins.getEnv "USER";
          homeDir = builtins.getEnv "HOME";
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit llmPkgs jjSyncPkg useDocker; };
          modules = [
            nix-config.homeModules.default
            ./home-manager/home.nix
            {
              home.username = username;
              home.homeDirectory = homeDir;
            }
          ];
        };

      # NixOS configuration (replaces entire OS)
      mkNixOS = { system, disk }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            disko.nixosModules.disko
            ./nixos/disk-config.nix
            ./nixos/configuration.nix
            {
              disko.devices.disk.disk1.device = disk;
            }
          ];
        };
    in
    {
      # Home-manager configurations (default, non-destructive)
      homeConfigurations = {
        # Non-NixOS (uses podman)
        "agent-x86_64-linux" = mkHome { system = "x86_64-linux"; };
        "agent-aarch64-linux" = mkHome { system = "aarch64-linux"; };
        # NixOS (uses docker)
        "nixos-agent-x86_64-linux" = mkHome { system = "x86_64-linux"; useDocker = true; };
        "nixos-agent-aarch64-linux" = mkHome { system = "aarch64-linux"; useDocker = true; };
      };

      # NixOS configurations (opt-in, replaces OS via nixos-anywhere)
      # Disk device is auto-detected by deploy script
      nixosConfigurations = {
        # x86_64 variants
        "agent-x86_64-sda" = mkNixOS { system = "x86_64-linux"; disk = "/dev/sda"; };
        "agent-x86_64-vda" = mkNixOS { system = "x86_64-linux"; disk = "/dev/vda"; };
        "agent-x86_64-nvme" = mkNixOS { system = "x86_64-linux"; disk = "/dev/nvme0n1"; };
        # aarch64 variants
        "agent-aarch64-sda" = mkNixOS { system = "aarch64-linux"; disk = "/dev/sda"; };
        "agent-aarch64-vda" = mkNixOS { system = "aarch64-linux"; disk = "/dev/vda"; };
        "agent-aarch64-nvme" = mkNixOS { system = "aarch64-linux"; disk = "/dev/nvme0n1"; };
      };
    };
}
