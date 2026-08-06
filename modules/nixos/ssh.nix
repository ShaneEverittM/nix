# Hardened, key-only sshd shared by every host. Behind the home router the hosts are
# reachable only from the LAN and the tailnet unless a port is forwarded.
{ ... }:

let
  identity = import ../../lib/identity.nix;
in
{
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ identity.username ];
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
