# One shared nixpkgs instantiation. Every place that imports a nixpkgs input by hand
# (flake packages + formatter, lib/checks.nix, the host assemblies) previously repeated
# the same incantation with the shared unfree predicate from ./nixpkgs-config.nix;
# `extraConfig` is the per-site widening hook (exodus sets `allowUnfree = true` for its
# GUI lane).
{
  input,
  system,
  extraConfig ? { },
}:
import input {
  inherit system;
  config = (import ./nixpkgs-config.nix { inherit (input) lib; }) // extraConfig;
}
