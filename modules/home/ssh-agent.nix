# 1Password SSH agent relay for WSL. Bridges the Windows-side 1Password SSH agent
# (exposed as a named pipe) to a Unix socket inside WSL, so ssh/git here can
# authenticate and sign using keys that never leave 1Password — nothing on disk.
#
# WSL-only: imported via modules/home/linux.nix, gated by the enable option.
# Requires, on the WINDOWS side (not Nix-managed — see README host setup):
#   * 1Password for Windows, Developer settings: "Use the SSH agent" enabled
#     (and "Integrate with 1Password CLI" if you also want `op`/signing);
#   * npiperelay.exe installed (e.g. `scoop install npiperelay`), path in the
#     publicHome.onepassword.npiperelay option below.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicHome.onepassword;
  sock = "${config.home.homeDirectory}/.1password/agent.sock";
in
{
  options.publicHome.onepassword = {
    sshAgentRelay = lib.mkEnableOption "the 1Password SSH agent relay (WSL → Windows named pipe)";

    npiperelay = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/c/Users/${config.publicHome.username}/scoop/shims/npiperelay.exe";
      description = "Path (WSL-visible) to npiperelay.exe on the Windows side.";
    };
  };

  config = lib.mkIf cfg.sshAgentRelay {
    home.packages = [ pkgs.socat ];

    # ssh and git (SSH signing) look here for the agent.
    home.sessionVariables.SSH_AUTH_SOCK = sock;

    # Start the relay lazily from the interactive shell rather than a systemd user
    # service: executing a Windows binary needs $WSL_INTEROP, which is per-session
    # and absent in boot-time services but present in an interactive shell. pgrep
    # guards against launching a second relay; setsid detaches it so it survives
    # the shell. Full store paths keep this independent of PATH.
    programs.zsh.initContent = lib.mkOrder 1500 ''
      if ! ${pkgs.procps}/bin/pgrep -f "UNIX-LISTEN:${sock}" >/dev/null 2>&1; then
        ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.1password"
        ${pkgs.coreutils}/bin/rm -f "${sock}"
        ( ${pkgs.util-linux}/bin/setsid ${pkgs.socat}/bin/socat \
            UNIX-LISTEN:"${sock}",fork \
            EXEC:"${cfg.npiperelay} -ei -s //./pipe/openssh-ssh-agent",nofork \
            >/dev/null 2>&1 & ) >/dev/null 2>&1
      fi
    '';
  };
}
