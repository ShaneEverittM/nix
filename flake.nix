{
  description = "Platform-agnostic Nix config: NixOS-WSL system + standalone home-manager for Linux/macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixos-wsl.url = "github:nix-community/NixOS-WSL/release-25.11";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      # Systems the convenience `packages.default` buildEnv is offered for.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # WSL host — `nixos-rebuild switch --flake .#nixos`.
      nixosConfigurations.nixos = import ./hosts/wsl/default.nix {
        inherit inputs;
        system = "x86_64-linux";
      };

      # Personal MacBook Air — `home-manager switch --flake .#shane@macbook`.
      # Evaluable anywhere, buildable only on a Darwin builder.
      homeConfigurations."shane@macbook" = import ./hosts/macbook/default.nix {
        inherit inputs;
        system = "aarch64-darwin";
      };

      # Convenience env of the shared package set for ad-hoc `nix profile install
      # .#default` on any machine. The real per-host consumption is via
      # home.packages (see lib/packages.nix).
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.buildEnv {
            name = "shane-packages";
            paths = import ./lib/packages.nix pkgs;
          };
        }
      );

      # Reusable modules, re-exported so a downstream (e.g. the private work-Mac
      # repo) can consume them as a flake input. The work Mac imports
      # homeModules.default + homeModules.darwin into a standalone home-manager
      # configuration.
      homeModules = {
        default = ./modules/home; # core bundle (common + git + shell + rust + bun)
        linux = ./modules/home/linux.nix; # WSL extras
        darwin = ./modules/home/darwin.nix; # Mac GUI bundle (vscode + warp + jetbrains)

        # Individual modules, for finer-grained downstream composition.
        common = ./modules/home/common.nix;
        git = ./modules/home/git.nix;
        shell = ./modules/home/shell.nix;
        rust = ./modules/home/rust.nix;
        bun = ./modules/home/bun.nix;
        vscode = ./modules/home/vscode.nix;
        warp = ./modules/home/warp.nix;
        jetbrains = ./modules/home/jetbrains.nix;
      };

      nixosModules = {
        default = ./modules/nixos/common.nix;
        wsl = ./modules/nixos/wsl.nix;
      };
    };
}
