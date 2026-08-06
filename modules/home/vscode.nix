# VS Code user settings/keybindings as out-of-store symlinks, so they stay live-
# editable in the checked-out repo (publicHome.repoRoot) rather than being copied
# read-only into the Nix store. Cross-platform (bundled via desktop.nix); the user
# config dir differs per OS, hence the split below.
{ config, pkgs, ... }:

let
  inherit (config.lib.publicHome) sourceFile;
  userConfigDir =
    if pkgs.stdenv.isDarwin then "Library/Application Support/Code/User" else ".config/Code/User";
in
{
  home.file = {
    "${userConfigDir}/settings.json" = {
      source = sourceFile "files/vscode/settings.json";
      force = true;
    };

    "${userConfigDir}/keybindings.json" = {
      source = sourceFile "files/vscode/keybindings.json";
      force = true;
    };
  };
}
