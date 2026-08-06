# Shared NixOS system config for the physical hosts (exodus + rebirth). Since WSL
# support was dropped, every NixOS host here is a bare-metal machine administered the
# same way, so this carries everything both boxes want identically: boot, locale,
# networking discovery, the shane account, hardened SSH, Tailscale, and the
# home-manager fold-in with the shared personal identity. Host files supply only what
# genuinely differs (hardware, desktop vs headless, per-host services).
#
# `inputs` is threaded in via specialArgs (see hosts/*/default.nix) so the
# home-manager module import and the nixPath pin below can reference this flake's own
# inputs.
{ inputs, pkgs, ... }:

let
  identity = import ../../lib/identity.nix;
in
{
  # NOTE: system.stateVersion is intentionally NOT set here — it is per-host (the
  # release each machine was first installed on) and would conflict between hosts that
  # were installed on different releases. Each host sets its own in
  # hosts/<name>/configuration.nix.

  imports = [
    # Fold home-manager into the system build, so one `nh os switch` applies
    # user-level config too — no separate home-manager CLI to invoke.
    inputs.home-manager.nixosModules.home-manager
  ];

  # Enable flakes and the new nix CLI system-wide.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # git must be available system-wide: nix needs it to read this git-based
  # flake on every `nixos-rebuild` (which runs as root via sudo).
  environment.systemPackages = with pkgs; [ git ];

  # Pin `<nixpkgs>` and `<home-manager>` to this flake's inputs so
  # channel-based tools (manix's option-doc search) can index both
  # NixOS and home-manager options without legacy `nix-channel` setup.
  # Both must be listed: setting nix.nixPath replaces the default
  # (flake:nixpkgs) entry rather than appending to it.
  nix.nixPath = [
    "nixpkgs=${inputs.nixpkgs}"
    "home-manager=${inputs.home-manager}"
  ];

  # Use systemd-boot as the boot manager, with EFI variables writable (rollback).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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

  # Personal machines: allow unfree packages. Broader than the shared
  # lib/nixpkgs-config.nix predicate (which the standalone home configs use).
  nixpkgs.config.allowUnfree = true;

  # zsh is the shared interactive shell (see modules/home/shell.nix). Enable it
  # system-wide and make it shane's login shell declaratively.
  programs.zsh.enable = true;

  # Primary user account. Set a password with `passwd` after a host's first switch.
  users.users."shane" = {
    isNormalUser = true;
    description = identity.userName;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
    # SSH in with the 1Password-held key (same key everywhere, incl. commit signing).
    openssh.authorizedKeys.keys = [ identity.sshPublicKey ];
  };

  # SSH access, key-only and hardened, on every host. Behind the home router the
  # hosts are reachable only from the LAN and the tailnet unless a port is forwarded.
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
      # The tailnet is trusted (device-authenticated WireGuard), so exempt it from
      # brute-force penalties: a flaky client or a locked 1Password agent retrying
      # over Tailscale must never be able to lock me out of my own remote access.
      # 100.64.0.0/10 is Tailscale's CGNAT range. LAN/WAN keeps the hardening.
      PerSourcePenaltyExemptList = "100.64.0.0/10";
    };
  };

  # mDNS: advertise/resolve `*.local` on the LAN so each box answers to
  # `<hostname>.local` without a static IP. nssmdns4 wires mDNS into nsswitch so it
  # resolves other `.local` hosts too; openFirewall opens UDP 5353.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # Tailscale: stable MagicDNS name + reachability from any tailnet device, LAN or
  # remote, over WireGuard. Enabling installs tailscaled + the CLI; join the tailnet
  # once with an interactive `tailscale up` (no key in this public repo).
  services.tailscale.enable = true;

  # Provide a real dynamic linker at the FHS path so prebuilt/foreign binaries can run
  # (e.g. Zed's remote SSH server, the Node-based Claude Code remote CLI).
  programs.nix-ld.enable = true;

  # Enable the NixOS-side nh so `nh os switch`/`nh os boot` work without a flake
  # path. NH_OS_FLAKE mirrors the home side's NH_HOME_FLAKE: both point at this
  # repo's checkout (publicHome.repoRoot defaults to ~/.config/nix).
  programs.nh = {
    enable = true;
    flake = "/home/shane/.config/nix";
  };

  # Shared home layer: every host gets the git module and the personal identity;
  # hosts stack their own bundles (exodus: core + linux + desktop) and host-specific
  # publicHome.* values on top. Importing git.nix here dedupes against hosts that
  # also pull it in via the core bundle — the module system imports a path once.
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.shane = {
    imports = [ ../home/git.nix ];

    # Personal git identity (already public). The work Mac sets its own in the
    # private nix-work repo.
    publicHome.git.userName = identity.userName;
    publicHome.git.userEmail = identity.userEmail;
    # Commit signing via the 1Password SSH key. How the signature is produced is
    # per-host (exodus routes through the 1Password GUI's op-ssh-sign; rebirth signs
    # via ssh-keygen + the forwarded agent).
    publicHome.git.signingKey = identity.sshPublicKey;
  };
}
