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

        # Bridge the Windows 1Password SSH agent into WSL (ssh + git auth without a
        # key on disk). Requires the Windows-side setup in the README. Override
        # `.npiperelay` if npiperelay.exe isn't at the scoop default path.
        publicHome.onepassword.sshAgentRelay = true;

        # Commit signing via the relayed 1Password key. DISABLED until you supply
        # your 1Password SSH *public* key below (safe to commit — it's public).
        # With the agent relayed, git signs via ssh-keygen using the agent — no
        # op-ssh-sign needed. git.nix turns on gpg.format=ssh + commit.gpgsign as
        # soon as signingKey is non-null.
        #   publicHome.git.signingKey = "ssh-ed25519 AAAA... (your 1Password key)";
        #
        # Alternative: drive signing through the Windows op-ssh-sign helper instead
        # of the agent (note: Linux→Windows temp-path translation can be finicky):
        #   publicHome.git.sshSigningProgram =
        #     "/mnt/c/Users/shane/AppData/Local/1Password/app/8/op-ssh-sign.exe";
      };
    }
    ../../modules/nixos/common.nix
    ../../modules/nixos/wsl.nix
  ];
}
