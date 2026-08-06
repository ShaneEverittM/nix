# The shared NixOS base for the physical hosts (exodus + rebirth), as a bundle of
# single-concern modules — the same shape as modules/home/default.nix. Hosts import
# this one file; a future host (or downstream consumer via nixosModules.*) can take
# the pieces à la carte instead.
#
# NOTE: system.stateVersion is intentionally NOT set anywhere in these modules — it is
# per-host (the release each machine was first installed on) and lives in
# hosts/<name>/configuration.nix.
{ ... }:
{
  imports = [
    ./core.nix # nix settings, boot, locale, base tooling, nh
    ./user.nix # shane account + the home-manager fold-in with identity
    ./ssh.nix # hardened key-only sshd
    ./network.nix # avahi mDNS + tailscale
  ];
}
