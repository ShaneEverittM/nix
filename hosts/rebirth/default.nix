# NixOS home-server assembly: the `nixosConfigurations.rebirth` system. Structurally a
# minimal sibling of hosts/exodus/default.nix — NixOS with home-manager folded in as a
# module — but headless: the home layer imports only the shared git module, not the
# core bundle or GUI dotfiles. Before the fold-in this box lived in its own repo
# (nix-server) and consumed this flake's exported homeModules.git as an input; living
# here, the module is imported directly and the input indirection is gone.
{ inputs, system }:

inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  # Thread the flake inputs to modules (modules/nixos/common.nix uses it for the
  # nixPath pin).
  specialArgs = { inherit inputs; };

  modules = [
    inputs.home-manager.nixosModules.home-manager
    ./configuration.nix
    ../../modules/nixos/common.nix
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.shane =
        { pkgs, ... }:
        {
          imports = [
            # Git behavior only (aliases, diff-so-fancy pager, LFS filters, colors);
            # this box is a server, not a workstation, so no core bundle or GUI
            # dotfiles. Identity is injected below via its publicHome.git options.
            ../../modules/home/git.nix
          ];

          # The git module expects these on PATH (see its header comment). Hosts that
          # import the core bundle get them from lib/packages.nix; this one doesn't.
          home.packages = with pkgs; [
            git-lfs
            diff-so-fancy
          ];

          # Personal git identity (already public), same as exodus.
          publicHome.git = {
            userName = "Shane Murphy";
            userEmail = "mail@semurphy.com";
            signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwRBMnr95gqzkvJHmNDCprKK2QcV2vNQVS6mAsGzcz3";
          };

          # The shared module signs commits; also sign tags.
          programs.git.settings.tag.gpgsign = true;

          # Home-manager's compatibility anchor, same idea as system.stateVersion.
          home.stateVersion = "26.05";
        };

      # Enable the NixOS-side nh so `nh os switch`/`nh os boot` work without a flake
      # path, against this repo's checkout on the box.
      programs.nh = {
        enable = true;
        flake = "/home/shane/.config/nix";
      };
    }
  ];
}
