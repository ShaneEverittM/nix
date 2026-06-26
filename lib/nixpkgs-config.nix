# Shared nixpkgs import config. Keep unfree allowances explicit and narrow.
{ lib }:

{
  allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "acli"
      "acli-unwrapped"
    ];
}
