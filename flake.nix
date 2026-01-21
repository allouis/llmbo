{
  description = "Home Manager configuration for LLM agent machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, llm-agents, ... }:
    let
      mkHome = { system }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          llmPkgs = llm-agents.packages.${system};
          # Use environment variables (requires --impure flag)
          username = builtins.getEnv "USER";
          homeDir = builtins.getEnv "HOME";
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit llmPkgs; };
          modules = [
            ./home.nix
            {
              home.username = username;
              home.homeDirectory = homeDir;
            }
          ];
        };
    in
    {
      homeConfigurations = {
        "agent-x86_64-linux" = mkHome { system = "x86_64-linux"; };
        "agent-aarch64-linux" = mkHome { system = "aarch64-linux"; };
      };
    };
}
