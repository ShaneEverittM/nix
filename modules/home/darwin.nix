# Mac-only home-manager bundle, shared by both Macs (personal MBA and work Mac).
# Imported alongside ./common.nix by the standalone home-manager configurations.
# Both Macs run home-manager standalone (no nix-darwin), so this is the only
# Mac-specific layer. It pulls in the GUI/terminal config (VS Code, Zed, Warp,
# JetBrains) whose out-of-store symlinks resolve against publicHome.repoRoot.
# (homeDirectory is derived in common.nix from publicHome.username.)
{ ... }:
{
  imports = [
    ./vscode.nix
    ./zed.nix
    ./warp.nix
    ./jetbrains.nix
  ];

  # Mac-only packages/config beyond the GUI modules go here as they come up.
}
