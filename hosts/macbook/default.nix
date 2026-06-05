# Personal MacBook Air assembly: a standalone home-manager configuration (no
# nix-darwin). Applied on the Mac with `nh home switch -c shane@macbook`.
# Evaluable from any system, but only buildable on a Darwin builder.
{ inputs, system }:

let
  pkgs = import inputs.nixpkgs { inherit system; };
  pkgsUnstable = import inputs.nixpkgs-unstable { inherit system; };
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  # Feed the warp.nix module its package options. local-oss is Shane's source-built
  # Warp fork (inputs.warp); stable is the nixpkgs binary. Only the source selected
  # by programs.warp.packageSource below is ever realized (lazy), and only on the Mac.
  extraSpecialArgs = {
    inherit pkgsUnstable;

    warpPackages = {
      local-oss = inputs.warp.packages.${system}.warp-terminal-experimental;
      stable = pkgs.warp-terminal;
    };
  };

  modules = [
    ../../modules/home # core bundle (common + git + shell + rust + bun)
    ../../modules/home/darwin.nix # Mac GUI bundle (vscode + warp + jetbrains)
    {
      # Personal git identity (already public). repoRoot defaults to ~/.config/nix,
      # which is also the default NH_HOME_FLAKE and out-of-store dotfile root.
      publicHome.git.userName = "Shane Murphy";
      publicHome.git.userEmail = "mail@shanemurphy.space";

      # Install the OSS Warp build from the fork.
      programs.warp.packageSource = "local-oss";
    }
  ];
}
