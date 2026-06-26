# WSL host assembly: the `nixosConfigurations.nixos` system. Pulls in the NixOS-WSL
# and home-manager modules from flake inputs, the platform-agnostic + WSL NixOS
# modules, and shane's home-manager config (common + linux).
{ inputs, system }:

let
  nixpkgsConfig = import ../../lib/nixpkgs-config.nix { lib = inputs.nixpkgs.lib; };
  pkgsUnstable = import inputs.nixpkgs-unstable {
    inherit system;
    config = nixpkgsConfig;
  };
in
inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  # Thread the flake inputs to modules (modules/nixos/common.nix uses it for the
  # nixPath pin).
  specialArgs = { inherit inputs; };

  modules = [
    inputs.nixos-wsl.nixosModules.default
    inputs.home-manager.nixosModules.home-manager
    {
      nixpkgs.config = nixpkgsConfig;

      home-manager.extraSpecialArgs = { inherit pkgsUnstable; };
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
        publicHome.git.userEmail = "mail@semurphy.com";

        # Bridge the Windows 1Password SSH agent into WSL (ssh + git auth without a
        # key on disk). Requires the Windows-side setup in the README.
        publicHome.onepassword.sshAgentRelay = true;
        # npiperelay installed via winget; its package folder is stable across
        # updates. (A full path is required here anyway — this config disables the
        # Windows PATH in WSL, see modules/nixos/wsl.nix.)
        publicHome.onepassword.npiperelay = "/mnt/c/Users/shane/AppData/Local/Microsoft/WinGet/Packages/albertony.npiperelay_Microsoft.Winget.Source_8wekyb3d8bbwe/npiperelay.exe";

        # Commit signing via the relayed 1Password key (same key as the sshd
        # authorizedKeys above). git signs through ssh-keygen + the agent — no
        # op-ssh-sign needed. git.nix enables gpg.format=ssh + commit.gpgsign and
        # wires an allowed-signers file for local verification.
        publicHome.git.signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwRBMnr95gqzkvJHmNDCprKK2QcV2vNQVS6mAsGzcz3";

        # Seed the Windows-side Warp install (settings.toml + JetBrains themes) so
        # WSL's Warp matches the Macs' shared profile. Warp here is a Windows app
        # reading %APPDATA%/%LOCALAPPDATA%; see modules/home/warp-wsl.nix.
        publicHome.warp.wslConfig = true;
      };

      # Enable the NixOS-side nh so `nh os switch`/`nh os boot` work without a
      # flake path. NH_OS_FLAKE mirrors the home side's NH_HOME_FLAKE: both point
      # at this repo's checkout (publicHome.repoRoot defaults to ~/.config/nix).
      programs.nh = {
        enable = true;
        flake = "/home/shane/.config/nix";
      };
    }
    ../../modules/nixos/common.nix
    ../../modules/nixos/wsl.nix
  ];
}
