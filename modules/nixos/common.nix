# Platform-agnostic NixOS system config — settings that apply to any NixOS host.
# Host-specific bits (WSL, hardware) live alongside this in ./wsl.nix etc.
#
# `inputs` is threaded in via specialArgs (see hosts/wsl/default.nix) so the nixPath
# pin below can reference this flake's own inputs.
{ inputs, pkgs, ... }:

{
  # NOTE: system.stateVersion is intentionally NOT set here — it is per-host (the
  # release each machine was first installed on) and would conflict between hosts that
  # were installed on different releases. Each host sets its own (WSL in
  # modules/nixos/wsl.nix, exodus in hosts/exodus/configuration.nix).

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
}
