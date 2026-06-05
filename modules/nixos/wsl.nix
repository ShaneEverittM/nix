# WSL host config: everything specific to running NixOS under WSL on this machine.
# The NixOS-WSL module itself is supplied by the flake input
# `nixos-wsl.nixosModules.default` (wired in hosts/wsl/default.nix).
{ pkgs, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "shane";

  # /mnt windows drives are owned by uid 1000 by default; point them at shane
  # (uid 1001) so the primary user owns them.
  wsl.wslConf.automount.options = "metadata,uid=1001,gid=100";

  # Don't append the Windows PATH to the Linux PATH. Those dirs contain files
  # with spaces in their names (e.g. "VmFirmware Third-Party Notices.txt"), and
  # tools that enumerate commands via `COMMANDS=($(compgen -c))` word-split them
  # into bogus tokens. Warp's command-highlight generator does exactly this, so
  # the stray fragments misalign its arrays and it underlines real, installed
  # commands as "not found". interop stays enabled — Windows exes are still
  # runnable by full path; they're just no longer on PATH by bare name.
  # NOTE: takes effect only after a `wsl --shutdown` (wsl.conf is read at boot).
  wsl.wslConf.interop.appendWindowsPath = false;

  # zsh is the shared interactive shell (see modules/home/shell.nix). Enable it
  # system-wide and make it shane's login shell — the NixOS-WSL default is bash,
  # and macOS already defaults to zsh, so this is the only place the login shell
  # needs setting declaratively.
  programs.zsh.enable = true;

  # Primary user. The NixOS-WSL module already makes the default user a normal,
  # wheel/sudo-capable account (uid defaults to 1000); we override the uid to
  # 1001 because the fallback `nixos` account still holds 1000, and add the key.
  users.users.shane = {
    uid = 1001;
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwRBMnr95gqzkvJHmNDCprKK2QcV2vNQVS6mAsGzcz3"
    ];
  };

  # Provide a real dynamic linker at the FHS path so prebuilt/foreign
  # binaries (e.g. the Node-based Claude Code remote CLI) can run on NixOS.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    openssl
  ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "shane" ];
      MaxAuthTries = 3;
      PerSourcePenalties = "crash:3600s authfail:3600s max:86400s";
    };
  };
}
