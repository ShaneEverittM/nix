# System configuration for `rebirth`, a repurposed laptop running headless NixOS as a
# lil' home server. Host assembly (home-manager, shared NixOS modules) lives in
# ./default.nix; this file is the system-only layer — hardware, networking, users, and
# services. Folded in from the formerly standalone nix-server repo (its pre-merge
# history lives at github:ShaneEverittM/nix-server), where this host was named `nixos`
# — renamed here because that attr belongs to the WSL host.
{ pkgs, ... }:

{
  imports = [
    # Grab the generated config from the installer, mostly just kernel modules and
    # filesystem mounts (btrfs subvolumes for /, /home, /nix; vfat /boot).
    ./hardware-configuration.nix
  ];

  # Use systemd-boot as the boot manager, with EFI variables writable (rollback).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "rebirth";

  # Configure wireless to autoconnect. The PSK is deliberately not in this public repo:
  # wpa_supplicant reads the `psk_Marconi` variable out of secretsFile — see the rebirth
  # notes in README.md for the bootstrap ritual that creates it.
  networking.wireless = {
    enable = true;
    secretsFile = "/etc/wpa_supplicant/wireless.conf";
    networks."Marconi".pskRaw = "ext:psk_Marconi";
  };

  # mDNS: advertise/resolve `*.local` on the LAN so this box answers to
  # `rebirth.local` without a static IP.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Set up the user account.
  users.users."shane" = {
    isNormalUser = true;
    description = "Shane Murphy";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    # SSH in with the 1Password-held key (same key as the other hosts and commit
    # signing).
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwRBMnr95gqzkvJHmNDCprKK2QcV2vNQVS6mAsGzcz3"
    ];
  };

  # Allow unfree packages, nothing currently but we aren't *that* much of a purist.
  nixpkgs.config.allowUnfree = true;

  # System-wide packages.
  environment.systemPackages = with pkgs; [
    # For bootstrapping edits before remote editors work.
    neovim
    # Nix language server (used by Zed over remote SSH).
    nixd
    # Nix formatter (again by Zed over remote SSH).
    nixfmt
    # System info at a glance.
    fastfetch
  ];

  # Enable OpenSSH daemon.
  services.openssh.enable = true;

  # Enable running non-nix-built binaries (Zed remote SSH server).
  programs.nix-ld.enable = true;

  # Headless server in a laptop chassis: closing the lid must not suspend it.
  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";
  services.logind.settings.Login.HandleLidSwitch = "ignore";

  # Compressed on-filesystem swap.
  zramSwap.enable = true;

  # This value determines the NixOS release from which the default settings for stateful
  # data (file locations, database versions) were taken. Leave it at the release of the
  # first install; per-host, so it lives here rather than in modules/nixos/common.nix.
  system.stateVersion = "26.05";
}
