{
  description = "NixOS-WSL system + home-manager for nixos@nixos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixos-wsl.url = "github:nix-community/NixOS-WSL/release-25.11";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      nixos-wsl,
      home-manager,
      ...
    }:
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixos-wsl.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.shane = import ./home.nix;
          }
          {
            # Pin `<nixpkgs>` and `<home-manager>` to this flake's inputs so
            # channel-based tools (manix's option-doc search) can index both
            # NixOS and home-manager options without legacy `nix-channel` setup.
            # Both must be listed: setting nix.nixPath replaces the default
            # (flake:nixpkgs) entry rather than appending to it.
            nix.nixPath = [
              "nixpkgs=${nixpkgs}"
              "home-manager=${home-manager}"
            ];
          }
          ./configuration.nix
        ];
      };
    };
}
