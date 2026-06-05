# VS Code user settings/keybindings as out-of-store symlinks, so they stay live-
# editable in the checked-out repo (publicHome.configRoot) rather than being copied
# read-only into the Nix store. Mac-only (bundled via darwin.nix): on WSL, VS Code
# runs on the Windows side, so writing the Linux config dir would be inert.
{ config, pkgs, ... }:

let
  publicRoot = ../..;
  sourceFile =
    path:
    if config.publicHome.dotfiles.mode == "outOfStore" then
      config.lib.file.mkOutOfStoreSymlink "${toString config.publicHome.repoRoot}/${path}"
    else
      publicRoot + "/${path}";
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
