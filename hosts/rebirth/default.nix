# NixOS home-server assembly: the `nixosConfigurations.rebirth` system. The shared
# base (modules/nixos/common.nix) supplies boot, locale, the shane account, hardened
# sshd, Tailscale, nh, and the home-manager fold-in with the git module + identity —
# so this file only stacks the server-appropriate home slice on top: the shared shell
# setup, but no core bundle, GUI dotfiles, or language toolchains. Before the fold-in
# this box lived in its own repo (nix-server) and consumed this flake's exported
# homeModules.git as an input; living here, the module comes from the shared base.
{ inputs, system }:

inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  # Thread the flake inputs to modules (modules/nixos/common.nix uses it for the
  # home-manager fold-in and the nixPath pin).
  specialArgs = { inherit inputs; };

  modules = [
    ./configuration.nix
    ../../modules/nixos/common.nix
    {
      home-manager.users.shane =
        { pkgs, ... }:
        {
          imports = [
            # zsh + aliases + zoxide/direnv, same interactive shell as everywhere
            # else (the login shell itself is set in the shared base).
            ../../modules/home/shell.nix
          ];

          # Tools the shared modules alias/expect on PATH (git.nix: git-lfs +
          # diff-so-fancy; shell.nix: eza + bat). Workstation hosts get these from
          # lib/packages.nix via the core bundle; this host stays à la carte.
          home.packages = with pkgs; [
            git-lfs
            diff-so-fancy
            eza
            bat
          ];

          # The shared module signs commits; also sign tags.
          programs.git.settings.tag.gpgsign = true;

          # Home-manager's compatibility anchor, same idea as system.stateVersion.
          home.stateVersion = "26.05";
        };
    }
  ];
}
