# Personal MacBook Air assembly: a standalone home-manager configuration (no
# nix-darwin). Applied on the Mac with `home-manager switch --flake .#shane@macbook`.
# Evaluable from any system, but only buildable on a Darwin builder.
{ inputs, system }:

inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = import inputs.nixpkgs { inherit system; };

  modules = [
    ../../modules/home/common.nix
    ../../modules/home/darwin.nix
  ];
}
