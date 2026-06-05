# VS Code user settings/keybindings as out-of-store symlinks, so they stay live-
# editable in the checked-out repo (publicHome.configRoot) rather than being copied
# read-only into the Nix store. Mac-only (bundled via darwin.nix): on WSL, VS Code
# runs on the Windows side, so writing the Linux config dir would be inert.
{ config, pkgs, ... }:

let
  configRoot = config.publicHome.configRoot;
  link = path: config.lib.file.mkOutOfStoreSymlink "${configRoot}/${path}";
  userConfigDir =
    if pkgs.stdenv.isDarwin then "Library/Application Support/Code/User" else ".config/Code/User";
in
{
  home.file = {
    "${userConfigDir}/settings.json" = {
      source = link "files/vscode/settings.json";
      force = true;
    };

    "${userConfigDir}/keybindings.json" = {
      source = link "files/vscode/keybindings.json";
      force = true;
    };
  };
}
