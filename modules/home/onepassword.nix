# Where SSH clients find the 1Password agent, as a typed option instead of a per-OS
# conditional scattered through the shell config. Part of the core bundle so every host
# can just flip it on.
#
# 1Password exposes the agent at a different path on each platform, and on WSL there is
# no native agent at all — ./ssh-agent.nix relays the Windows named pipe to a socket at
# the Linux default path below. So the three hosts differ only in the value:
#
#   macOS   ~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock  (native)
#   Linux   ~/.1password/agent.sock                                          (native)
#   WSL     ~/.1password/agent.sock                                          (relayed)
#
# Signing is the other half and stays in publicHome.git.sshSigningProgram, because the
# signer binary's path is machine-specific (/Applications/... on macOS,
# /opt/1Password/op-ssh-sign on Linux) and WSL signs through ssh-keygen + the relayed
# agent with no signer binary at all.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicHome.onepassword;
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
    home.sessionVariables.SSH_AUTH_SOCK = cfg.sshAuthSock;
  };
}
