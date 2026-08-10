# Home-manager owns ~/.ssh/config on the workstations, so the SSH client config is
# versioned like everything else. This module owns the file itself (enable) plus the
# aliases for the hosts in this repo; ./onepassword.nix contributes the IdentityAgent
# rules into the same programs.ssh.settings DAG when the 1Password agent is in use.
#
# ssh_config takes the FIRST value it sees for a keyword, so block order is
# load-bearing: the Include and the per-host blocks must land above the "Host *"
# block that onepassword.nix appends. Hence the entryBefore ordering below —
# "forwarded-agent" is named too, only so the file reads hosts-then-agent-rules
# rather than interleaved. Both names are onepassword.nix's, and a DAG edge to an
# absent entry is a no-op, so this still sorts fine when sshAgent is off.
{ config, lib, ... }:

let
  cfg = config.publicHome;
in
{
  programs.ssh = {
    enable = true;

    # Don't inject home-manager's opinionated default "Host *" block (Compression,
    # ServerAliveInterval, ControlMaster, …). The only "Host *" settings this repo
    # wants are the ones onepassword.nix declares as the "default" entry.
    enableDefaultConfig = false;

    # Escape hatch for hosts that shouldn't be in a public repo (a bare WAN address
    # is someone's home IP) or that are specific to one machine. Unmanaged and
    # git-ignored by virtue of living outside the checkout; OpenSSH silently skips
    # the Include when the file is absent, so this costs nothing on hosts without
    # one. Rendered above every block below, so a local entry wins.
    includes = [ "config.local" ];

    settings = {
      # The NixOS hosts in this repo. Both resolve by bare name over the LAN (avahi
      # in modules/nixos/network.nix) or Tailscale, so no HostName is needed.
      # ForwardAgent so the 1Password agent on the workstation signs git commits and
      # authenticates pushes from a shell on the server, which runs no 1Password.
      rebirth = lib.hm.dag.entryBefore [ "forwarded-agent" "default" ] {
        User = cfg.username;
        ForwardAgent = true;
      };

      exodus = lib.hm.dag.entryBefore [ "forwarded-agent" "default" ] {
        User = cfg.username;
        ForwardAgent = true;
      };
    };
  };
}
