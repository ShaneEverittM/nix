# Core system baseline shared by every NixOS host: the nix CLI itself, boot manager,
# locale, root-usable tooling, and the nh wrapper. Deliberately not split further —
# boot/locale are two lines each and don't earn their own files.
#
# `inputs` is threaded in via specialArgs (see hosts/*/default.nix) so the nixPath
# pin below can reference this flake's own inputs.
{ inputs, pkgs, ... }:

let
  identity = import ../../lib/identity.nix;
in
{
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

  # Provide a real dynamic linker at the FHS path so prebuilt/foreign binaries can run
  # (e.g. Zed's remote SSH server, the Node-based Claude Code remote CLI).
  programs.nix-ld.enable = true;

  # Enable the NixOS-side nh so `nh os switch`/`nh os boot` work without a flake
  # path. NH_OS_FLAKE mirrors the home side's NH_HOME_FLAKE: both point at this
  # repo's checkout (publicHome.repoRoot defaults to ~/.config/nix).
  programs.nh = {
    enable = true;
    flake = "/home/${identity.username}/.config/nix";
  };
}
