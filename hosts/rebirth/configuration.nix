# System configuration for `rebirth`, a repurposed laptop running headless NixOS as a
# lil' home server. Host assembly (home-manager, shared NixOS modules) lives in
# ./default.nix; this file is the system-only layer — hardware, networking, and
# server-specific services. Folded in from the formerly standalone nix-server repo
# (its pre-merge history lives at github:ShaneEverittM/nix-server), where this host
# was named `nixos` — renamed on merge because that attr then belonged to the
# since-dropped WSL host.
{ pkgs, ... }:

{
  imports = [
    # Grab the generated config from the installer, mostly just kernel modules and
    # filesystem mounts (btrfs subvolumes for /, /home, /nix; vfat /boot).
    ./hardware-configuration.nix
  ];

  networking.hostName = "rebirth";

  # Configure wireless to autoconnect. The PSK is deliberately not in this public repo:
  # wpa_supplicant reads the `psk_Marconi` variable out of secretsFile — see the rebirth
  # notes in README.md for the bootstrap ritual that creates it.
  networking.wireless = {
    enable = true;
    secretsFile = "/etc/wpa_supplicant/wireless.conf";
    networks."Marconi".pskRaw = "ext:psk_Marconi";
  };

  # systemd-resolved, so Tailscale configures split DNS over D-Bus (tailnet domains →
  # 100.100.100.100, everything else → the DHCP resolver) instead of capturing and
  # overwriting /etc/resolv.conf. Without it, tailscaled races dhcpcd at boot on this
  # slow-associating Wi-Fi host: it captures resolv.conf before the DHCP nameserver
  # lands, ends up with an empty upstream list, and every non-tailnet DNS query fails
  # (observed post-`tailscale up`: MagicDNS names resolved, nothing else did).
  # exodus doesn't need this — NetworkManager owns resolv.conf there.
  services.resolved.enable = true;

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
