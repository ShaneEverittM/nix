# Mac-only home-manager bundle, shared by both Macs (personal MBA and work Mac).
# Imported alongside ./common.nix by the standalone home-manager configurations.
# Both Macs run home-manager standalone (no nix-darwin), so this is the only
# Mac-specific layer. The GUI/terminal config it used to own directly now lives in
# ./desktop.nix, which native Linux desktop hosts share.
# (homeDirectory is derived in common.nix from publicHome.username.)
{ ... }:
{
  imports = [
    ./desktop.nix # cross-platform GUI dotfiles (vscode + zed + warp + jetbrains)
  ];

  # Mac-only packages/config beyond the desktop bundle go here as they come up.
}
