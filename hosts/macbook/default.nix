# Personal MacBook Air assembly: a standalone home-manager configuration (no
# nix-darwin). Applied on the Mac with `home-manager switch --flake .#shane@macbook`.
# Evaluable from any system, but only buildable on a Darwin builder.
{ inputs, system }:

inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = import inputs.nixpkgs { inherit system; };

  modules = [
    ../../modules/home # core bundle (common + git + shell + rust + bun)
    ../../modules/home/darwin.nix # Mac GUI bundle (vscode + warp + jetbrains)
    {
      # Personal git identity (already public). configRoot defaults to
      # ~/.config/home-manager — where the hm.ts workflow expects the checkout, and
      # what the vscode/warp out-of-store symlinks resolve against.
      publicHome.git.userName = "Shane Murphy";
      publicHome.git.userEmail = "mail@shanemurphy.space";
    }
  ];
}
