# Personal MacBook Air assembly: a standalone home-manager configuration (no
# nix-darwin). Applied on the Mac with `nh home switch -c shane@macbook`.
# Evaluable from any system, but only buildable on a Darwin builder.
{ inputs, system }:

let
  identity = import ../../lib/identity.nix;
  mkPkgs = import ../../lib/mk-pkgs.nix;
  pkgs = mkPkgs {
    input = inputs.nixpkgs;
    inherit system;
  };
  pkgsUnstable = mkPkgs {
    input = inputs.nixpkgs-unstable;
    inherit system;
  };
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  extraSpecialArgs = {
    inherit pkgsUnstable;
  };

  modules = [
    ../../modules/home # core bundle (common + git + onepassword + shell + rust + bun + java)
    ../../modules/home/darwin.nix # Mac GUI bundle (vscode + zed + warp + jetbrains)
    {
      # Personal git identity, single-sourced (already public). repoRoot defaults to
      # ~/.config/nix, which is also the default NH_HOME_FLAKE and out-of-store
      # dotfile root.
      publicHome.git.userName = identity.userName;
      publicHome.git.userEmail = identity.userEmail;

      # Commit signing via the 1Password SSH key (same key everywhere). On macOS the
      # native 1Password app exposes op-ssh-sign; git.nix enables gpg.format=ssh +
      # commit.gpgsign, routes signing through this program, and wires an
      # allowed-signers file for local verification.
      publicHome.git.signingKey = identity.sshPublicKey;
      publicHome.git.sshSigningProgram = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";

      # Warp itself is installed via Homebrew (Brewfile cask); Nix only manages its
      # config (settings/themes/keybindings under ~/.warp via modules/home/warp.nix).
    }
  ];
}
