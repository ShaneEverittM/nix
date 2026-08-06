# Shared Linux home-manager layer: things true of every Linux host, whether it runs
# NixOS or not. Imported directly by native Linux hosts alongside ./generic-linux.nix
# on non-NixOS distros.
#
# Keep the non-NixOS distro workarounds out of here, since NixOS hosts must not get
# them; those live in ./generic-linux.nix.
_: {
  # Linux-wide packages/config shared by Linux hosts go here as they come up.
  # (homeDirectory is derived in common.nix from publicHome.username.)
}
