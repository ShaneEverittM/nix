# Single source for where each modpack lives on disk. Kept as plain data (no module
# system) because it has two consumers that can't share an evaluated config: the
# instance definitions in ./default.nix, and tests/minecraft-console.nix, which needs
# the path as a *string* to interpolate into its Python test script.
#
# These are host paths, and each is shared into its pack's guest at the same path (see
# ./host.nix), so the one string is right on both sides of the VM boundary.
#
# The volume-relative world path btrbk wants is NOT here — ./options.nix derives it as a
# read-only per-server option, and ../btrbk.nix reads it back off the config.
{
  craftoria = "/var/lib/minecraft/craftoria";
  atm10 = "/var/lib/minecraft/atm10";
}
