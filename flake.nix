{
  description = "Platform-agnostic Nix config: NixOS-WSL system + standalone home-manager for Linux/macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Small package lane for cross-host tools that need to move faster than nixos-25.11.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nixos-wsl.url = "github:nix-community/NixOS-WSL/release-25.11";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      nixpkgsConfig = import ./lib/nixpkgs-config.nix { lib = nixpkgs.lib; };

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

      # Personal MacBook Air — `nh home switch`.
      # Evaluable anywhere, buildable only on a Darwin builder.
      homeConfigurations =
        let
          macbook = import ./hosts/macbook/default.nix {
            inherit inputs;
            system = "aarch64-darwin";
          };
        in
        {
          "shane@macbook" = macbook;

          # nh home auto-detects <username>@<hostname>, then <username>. Keep
          # this alias so the public Mac can use the short nh home commands even
          # when its hostname is not literally "macbook".
          shane = macbook;
        };

      # Convenience env of the shared package set for ad-hoc `nix profile install
      # .#default` on any machine. The real per-host consumption is via
      # home.packages (see lib/packages.nix).
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = nixpkgsConfig;
          };
          pkgsUnstable = import inputs.nixpkgs-unstable {
            inherit system;
            config = nixpkgsConfig;
          };
        in
        {
          default = pkgs.buildEnv {
            name = "shane-packages";
            paths = import ./lib/packages.nix pkgs ++ import ./lib/unstable-packages.nix pkgsUnstable;
          };
        }
      );

      # Reusable modules, re-exported so a downstream (e.g. the private work-Mac
      # repo) can consume them as a flake input. The work Mac imports
      # homeModules.default + homeModules.darwin into a standalone home-manager
      # configuration.
      homeModules = {
        default = import ./modules/home; # core bundle (common + git + shell + rust + bun)
        linux = import ./modules/home/linux.nix; # WSL extras
        darwin = import ./modules/home/darwin.nix; # Mac GUI bundle (vscode + zed + warp + jetbrains)

        # Individual modules, for finer-grained downstream composition.
        common = import ./modules/home/common.nix;
        git = import ./modules/home/git.nix;
        shell = import ./modules/home/shell.nix;
        rust = import ./modules/home/rust.nix;
        bun = import ./modules/home/bun.nix;
        vscode = import ./modules/home/vscode.nix;
        zed = import ./modules/home/zed.nix;
        warp = import ./modules/home/warp.nix;
        jetbrains = import ./modules/home/jetbrains.nix;
      };

      nixosModules = {
        default = import ./modules/nixos/common.nix;
        wsl = import ./modules/nixos/wsl.nix;
      };
    };
}
