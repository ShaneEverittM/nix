# Shared Linux home-manager layer: things true of every Linux host, whether it runs
# NixOS or not, WSL or bare metal. Imported by ./wsl.nix (WSL) and directly by native
# Linux hosts alongside ./generic-linux.nix.
#
# Keep the Windows-facing bits out of here — those belong in ./wsl.nix — and keep the
# non-NixOS distro workarounds out too, since NixOS hosts must not get them; those live
# in ./generic-linux.nix.
_: {
  # Linux-wide packages/config shared by WSL and desktop Linux go here as they come up.
  # (homeDirectory is derived in common.nix from publicHome.username.)
}
