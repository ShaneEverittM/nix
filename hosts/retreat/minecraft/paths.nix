# Single source for where each modpack lives on disk. Kept as plain data (no module
# system) because it has two consumers that can't share an evaluated config: the
# instance definitions in ./default.nix, and tests/minecraft-console.nix, which needs
# the path as a *string* to interpolate into its Python test script.
#
# The volume-relative world path btrbk wants is NOT here — ./service.nix derives it as a
# read-only per-server option, and ../btrbk.nix reads it back off the config.
{
  craftoria = "/home/shane/Servers/minecraft/craftoria2";
  atm10 = "/home/shane/Servers/minecraft/atm10";
}
