{
  description = "Platform-agnostic Nix config: NixOS hosts (desktop + home server) + standalone home-manager for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Small package lane for cross-host tools that need to move faster than nixos-26.05.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      # Shared nixpkgs instantiation (unfree predicate baked in) — see lib/mk-pkgs.nix.
      mkPkgs = import ./lib/mk-pkgs.nix;

      # Systems the convenience `packages.default` buildEnv is offered for.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Bare-metal KDE desktop — `nixos-rebuild switch --flake .#exodus` (or `nh os
      # switch`). Formerly a standalone home-manager config on CachyOS; now full NixOS
      # with home-manager folded in (see hosts/exodus/default.nix).
      nixosConfigurations.exodus = import ./hosts/exodus/default.nix {
        inherit inputs;
        system = "x86_64-linux";
      };
      # Headless home server (repurposed laptop) — `nixos-rebuild switch --flake
      # .#rebirth` (or `nh os switch`). Folded in from the formerly standalone
      # nix-server repo (see hosts/rebirth/default.nix).
      nixosConfigurations.rebirth = import ./hosts/rebirth/default.nix {
        inherit inputs;
        system = "x86_64-linux";
      };

      # Standalone home-manager hosts (no nix-darwin, no NixOS): the personal Mac. The
      # Mac config is evaluable anywhere but buildable only on a Darwin builder.
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
          # when its hostname is not literally "macbook". The Linux host is matched
          # by its exact <username>@<hostname> above, so it never reaches this
          # Darwin-only fallback.
          shane = macbook;
        };

      # Convenience env of the shared package set for ad-hoc `nix profile install
      # .#default` on any machine. The real per-host consumption is via
      # home.packages (see lib/packages.nix).
      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs {
            input = nixpkgs;
            inherit system;
          };
          pkgsUnstable = mkPkgs {
            input = inputs.nixpkgs-unstable;
            inherit system;
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
        default = import ./modules/home; # core bundle (common + git + onepassword + shell + rust + bun + java)
        linux = import ./modules/home/linux.nix; # shared Linux layer
        genericLinux = import ./modules/home/generic-linux.nix; # non-NixOS distro fixups
        darwin = import ./modules/home/darwin.nix; # Mac layer (pulls in desktop)
        desktop = import ./modules/home/desktop.nix; # GUI bundle (vscode + zed + warp + jetbrains)

        # Individual modules, for finer-grained downstream composition.
        common = import ./modules/home/common.nix;
        git = import ./modules/home/git.nix;
        shell = import ./modules/home/shell.nix;
        rust = import ./modules/home/rust.nix;
        bun = import ./modules/home/bun.nix;
        java = import ./modules/home/java.nix;
        onepassword = import ./modules/home/onepassword.nix;
        vscode = import ./modules/home/vscode.nix;
        zed = import ./modules/home/zed.nix;
        warp = import ./modules/home/warp.nix;
        jetbrains = import ./modules/home/jetbrains.nix;
      };

      nixosModules = {
        default = import ./modules/nixos/common.nix;
      };

      # CI gates as flake checks, so `nix flake check` runs the same lint + build
      # coverage locally and in CI. See lib/checks.nix for the per-system split.
      checks = import ./lib/checks.nix { inherit inputs self systems; };

      # `nix fmt` formats the tree with the same tool the nixfmt check enforces.
      formatter = forAllSystems (
        system:
        (mkPkgs {
          input = nixpkgs;
          inherit system;
        }).nixfmt
      );
    };
}
