# Personal MacBook Air assembly: a standalone home-manager configuration (no
# nix-darwin). Applied on the Mac with `nh home switch -c shane@macbook`.
# Evaluable from any system, but only buildable on a Darwin builder.
{ inputs, system }:

let
  nixpkgsConfig = import ../../lib/nixpkgs-config.nix { lib = inputs.nixpkgs.lib; };
  pkgs = import inputs.nixpkgs {
    inherit system;
    config = nixpkgsConfig;
  };
  pkgsUnstable = import inputs.nixpkgs-unstable {
    inherit system;
    config = nixpkgsConfig;
  };
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  extraSpecialArgs = {
    inherit pkgsUnstable;
  };

  modules = [
    ../../modules/home # core bundle (common + git + shell + rust + bun)
    ../../modules/home/darwin.nix # Mac GUI bundle (vscode + warp + jetbrains)
    {
      # Personal git identity (already public). repoRoot defaults to ~/.config/nix,
      # which is also the default NH_HOME_FLAKE and out-of-store dotfile root.
      publicHome.git.userName = "Shane Murphy";
      publicHome.git.userEmail = "mail@semurphy.com";

      # Commit signing via the 1Password SSH key (same key as WSL). On macOS the
      # native 1Password app exposes op-ssh-sign; git.nix enables gpg.format=ssh +
      # commit.gpgsign, routes signing through this program, and wires an
      # allowed-signers file for local verification.
      publicHome.git.signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwRBMnr95gqzkvJHmNDCprKK2QcV2vNQVS6mAsGzcz3";
      publicHome.git.sshSigningProgram = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";

      # Warp itself is installed via Homebrew (Brewfile cask); Nix only manages its
      # config (settings/themes/keybindings under ~/.warp via modules/home/warp.nix).
    }
  ];
}
