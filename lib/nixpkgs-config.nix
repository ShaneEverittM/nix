# Shared nixpkgs import config. Keep unfree allowances explicit and narrow.
#
# Deliberate asymmetry: this narrow predicate governs the standalone home configs
# (macbook, the downstream CI checks, `packages.default`), while the NixOS hosts set a
# blanket `nixpkgs.config.allowUnfree = true` in modules/nixos — those are personal
# machines that install unfree GUI apps (1Password, Warp, VS Code, JetBrains, Discord),
# and their allowance deliberately does not leak into the exported home modules.
{ lib }:

{
  allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "acli"
      "acli-unwrapped"
    ];
}
