# Zed settings/keymap as out-of-store symlinks, so they stay live-editable in the
# checked-out repo. Cross-platform (bundled via desktop.nix): Zed reads ~/.config/zed on
# both macOS and Linux, so no per-OS path split is needed here.
{ config, ... }:

let
  publicRoot = ../..;
  sourceFile =
    path:
    if config.publicHome.dotfiles.mode == "outOfStore" then
      config.lib.file.mkOutOfStoreSymlink "${toString config.publicHome.repoRoot}/${path}"
    else
      publicRoot + "/${path}";
in
{
  home.file = {
    ".config/zed/settings.json" = {
      source = sourceFile "files/zed/settings.json";
      force = true;
    };

    ".config/zed/keymap.json" = {
      source = sourceFile "files/zed/keymap.json";
      force = true;
    };
  };
}
