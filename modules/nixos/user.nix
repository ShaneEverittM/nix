# The shane account and the home-manager fold-in, wired to lib/identity.nix.
#
# `inputs` is threaded in via specialArgs (see hosts/*/default.nix) so the
# home-manager NixOS module can be imported from the flake input here.
{ inputs, pkgs, ... }:

let
  identity = import ../../lib/identity.nix;
in
{
  imports = [
    # Fold home-manager into the system build, so one `nh os switch` applies
    # user-level config too — no separate home-manager CLI to invoke.
    inputs.home-manager.nixosModules.home-manager
  ];

  # zsh is the shared interactive shell (see modules/home/shell.nix). Enable it
  # system-wide and make it shane's login shell declaratively.
  programs.zsh.enable = true;

  # Primary user account. Set a password with `passwd` after a host's first switch.
  users.users.${identity.username} = {
    isNormalUser = true;
    description = identity.userName;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
    # SSH in with the 1Password-held key (same key everywhere, incl. commit signing).
    openssh.authorizedKeys.keys = [ identity.sshPublicKey ];
  };

  # Shared home layer: every host gets the git module and the personal identity;
  # hosts stack their own bundles (exodus: core + linux + desktop) and host-specific
  # publicHome.* values on top. Importing git.nix here dedupes against hosts that
  # also pull it in via the core bundle — the module system imports a path once.
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.${identity.username} = {
    imports = [ ../home/git.nix ];

    # Personal git identity (already public). The work Mac sets its own in the
    # private nix-work repo.
    publicHome.git.userName = identity.userName;
    publicHome.git.userEmail = identity.userEmail;
    # Commit signing via the 1Password SSH key. How the signature is produced is
    # per-host (exodus routes through the 1Password GUI's op-ssh-sign; rebirth signs
    # via ssh-keygen + the forwarded agent).
    publicHome.git.signingKey = identity.sshPublicKey;
  };
}
