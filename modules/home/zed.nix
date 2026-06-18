# Zed settings/keymap as out-of-store symlinks, so they stay live-editable in the
# checked-out repo. Mac-only for now (bundled via darwin.nix): this repo does not
# currently model a Linux desktop Zed install.
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
