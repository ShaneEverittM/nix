# Hardened, key-only sshd shared by every host. Behind the home router the hosts are
# reachable only from the LAN and the tailnet unless a port is forwarded.
{ config, lib, ... }:

let
  identity = import ../../lib/identity.nix;
  cfg = config.publicNixos.ssh;
in
{
  options.publicNixos.ssh.extraAllowUsers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "btrbk" ];
    description = ''
      Extra accounts to append to sshd's AllowUsers, on top of the primary login
      user. For non-interactive service accounts that must accept SSH on some hosts
      (e.g. the btrbk receive user on a backup target) but whose keys are otherwise
      pinned to a forced command.
    '';
  };

  config.services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      # Primary login account, plus any service accounts a host opts into via
      # publicNixos.ssh.extraAllowUsers (e.g. rebirth's btrbk receive user).
      AllowUsers = [ identity.username ] ++ cfg.extraAllowUsers;
      MaxAuthTries = 3;
      PerSourcePenalties = "crash:3600s authfail:3600s max:86400s";
      # The tailnet is trusted (device-authenticated WireGuard), so exempt it from
      # brute-force penalties: a flaky client or a locked 1Password agent retrying
      # over Tailscale must never be able to lock me out of my own remote access.
      # 100.64.0.0/10 is Tailscale's CGNAT range. LAN/WAN keeps the hardening.
      PerSourcePenaltyExemptList = "100.64.0.0/10";
    };
  };
}
