# Single source for the Craftoria server's on-disk location. Two files must agree on
# it — ./craftoria.nix (absolute serverDir the unit runs in) and ./btrbk.nix (the
# world subvolume, as a path relative to the btrfs volume mounted at /) — and this
# file is the agreement.
rec {
  serverDir = "/home/shane/Servers/minecraft/craftoria2";
  # btrbk wants the volume-relative form: the absolute path minus the leading slash,
  # plus the world subvolume created inside it (see the NOCOW ritual in craftoria.nix).
  worldSubvolume = builtins.substring 1 (-1) serverDir + "/world";
}
