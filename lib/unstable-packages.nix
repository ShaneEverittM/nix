# Cross-host packages intentionally sourced from nixpkgs-unstable because their
# release cadence matters more than staying on the baseline nixos-25.11 package set.
# Keep this list small and platform-agnostic.
pkgs: with pkgs; [
  # Polyglot runtime version manager (activated in modules/home/shell.nix).
  mise
  # The Atlassian CLI.
  acli
]
