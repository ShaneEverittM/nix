# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL

# NOTE: This config is now built as a flake (see ./flake.nix). The NixOS-WSL
# module is supplied by the flake input `nixos-wsl.nixosModules.default`, so
# the old `imports = [ <nixos-wsl/modules> ];` channel import has been removed.

{ pkgs, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "shane";

  # /mnt windows drives are owned by uid 1000 by default; point them at shane
  # (uid 1001) so the primary user owns them.
  wsl.wslConf.automount.options = "metadata,uid=1001,gid=100";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

  # Enable flakes and the new nix CLI system-wide.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # git must be available system-wide: nix needs it to read this git-based
  # flake on every `nixos-rebuild` (which runs as root via sudo).
  environment.systemPackages = with pkgs; [ git ];

  # Primary user. The NixOS-WSL module already makes the default user a normal,
  # wheel/sudo-capable account (uid defaults to 1000); we override the uid to
  # 1001 because the fallback `nixos` account still holds 1000, and add the key.
  users.users.shane = {
    uid = 1001;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwRBMnr95gqzkvJHmNDCprKK2QcV2vNQVS6mAsGzcz3"
    ];
  };

  # Fallback account kept during the rename — remove once shane is confirmed.
  users.users.nixos = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" ];
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
      AllowUsers = [ "nixos" ];
      MaxAuthTries = 3;
      PerSourcePenalties = "crash:3600s authfail:3600s max:86400s";
    };
  };
}
