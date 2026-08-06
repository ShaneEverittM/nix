# Where SSH clients find the 1Password agent, as a typed option instead of a per-OS
# conditional scattered through the shell config. Part of the workstation core bundle
# so any host running the 1Password app can just flip it on (rebirth runs no 1Password
# and signs/authenticates via the SSH agent forwarded from a workstation).
#
# 1Password exposes the agent at a different path on each platform, so the hosts
# differ only in the value:
#
#   macOS   ~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock  (native)
#   Linux   ~/.1password/agent.sock                                          (native)
#
# Signing is the other half and stays in publicHome.git.sshSigningProgram, because the
# signer binary's path is machine-specific (/Applications/... on macOS, a store path
# on NixOS); a host with no signer binary signs through ssh-keygen + the agent.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicHome.onepassword;

  # Keep a live agent forwarded over SSH (ForwardAgent: SSH_CONNECTION set + the
  # socket sshd created still present); otherwise point at this host's own
  # 1Password socket.
  preferForwardedAgent = ''
    if [ -z "''${SSH_CONNECTION:-}" ] || [ ! -S "''${SSH_AUTH_SOCK:-}" ]; then
      export SSH_AUTH_SOCK="${cfg.sshAuthSock}"
    fi
  '';
in
{
  options.publicHome.onepassword = {
    sshAgent = lib.mkOption {
      type = lib.types.bool;
      # Both Macs have the native agent, and defaulting on there preserves the behavior
      # this replaced (an isDarwin export in shell.nix) for downstream consumers. Linux
      # hosts opt in: a bare Linux box need not have 1Password installed, and pointing
      # SSH_AUTH_SOCK at a socket that never appears breaks ssh rather than falling back.
      default = pkgs.stdenv.isDarwin;
      description = "Point SSH_AUTH_SOCK at the 1Password SSH agent socket.";
    };

    sshAuthSock = lib.mkOption {
      type = lib.types.str;
      default =
        if pkgs.stdenv.isDarwin then
          "${config.publicHome.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
        else
          "${config.publicHome.homeDirectory}/.1password/agent.sock";
      description = "Path to the 1Password SSH agent socket. Defaults to the platform-standard location.";
    };
  };

  config = lib.mkIf cfg.sshAgent {
    # Deliberately not home.sessionVariables: that writes an unconditional
    # `export SSH_AUTH_SOCK=…` into .zshenv, which runs on every shell and
    # overwrites the socket sshd forwards into an `ssh -A` session (leaving remote
    # sessions pointed at a local 1Password agent that isn't running headless). So
    # set it conditionally instead, covering the same shells home.sessionVariables
    # did — zsh's .zshenv (envExtra) and bash's .profile/.bash_profile
    # (profileExtra) — to keep login/GUI coverage unchanged.
    programs.zsh.envExtra = preferForwardedAgent;
    programs.bash.profileExtra = preferForwardedAgent;

    # IdentityAgent overrides SSH_AUTH_SOCK, so it needs the same forwarded-vs-local
    # split as the shell logic above — otherwise ssh/git ignore a forwarded agent and
    # get pinned to this host's 1Password socket (dead in a headless SSH session).
    # The Match-exec block must sort before "*" (first value wins in ssh_config).
    programs.ssh = {
      enable = true;
      # Don't inject home-manager's default Host * block; we only want the two
      # IdentityAgent rules below, matching the prior hand-written config.
      enableDefaultConfig = false;
      settings = {
        forwarded-agent = lib.hm.dag.entryBefore [ "default" ] {
          header = ''Match exec "test -n \"$SSH_CONNECTION\""'';
          IdentityAgent = "SSH_AUTH_SOCK";
        };
        default = {
          header = "Host *";
          # Quoted because the macOS socket path contains spaces.
          IdentityAgent = ''"${cfg.sshAuthSock}"'';
        };
      };
    };
  };
}
