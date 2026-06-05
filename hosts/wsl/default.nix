# WSL host assembly: the `nixosConfigurations.nixos` system. Pulls in the NixOS-WSL
# and home-manager modules from flake inputs, the platform-agnostic + WSL NixOS
# modules, and shane's home-manager config (common + linux).
{ inputs, system }:

inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  # Thread the flake inputs to modules (modules/nixos/common.nix uses it for the
  # nixPath pin).
  specialArgs = { inherit inputs; };

  modules = [
    inputs.nixos-wsl.nixosModules.default
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.shane = {
        imports = [
          ../../modules/home # core bundle (common + git + shell + rust + bun)
          ../../modules/home/linux.nix
        ];
        # Personal git identity (already public). The work Mac sets its own in the
        # private nix-work repo.
        publicHome.git.userName = "Shane Murphy";
        publicHome.git.userEmail = "mail@shanemurphy.space";
      };
    }
    ../../modules/nixos/common.nix
    ../../modules/nixos/wsl.nix
  ];
}
