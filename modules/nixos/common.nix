# Platform-agnostic NixOS system config — settings that apply to any NixOS host.
# Host-specific bits (WSL, hardware) live alongside this in ./wsl.nix etc.
#
# `inputs` is threaded in via specialArgs (see hosts/wsl/default.nix) so the nixPath
# pin below can reference this flake's own inputs.
{ inputs, pkgs, ... }:

{
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
