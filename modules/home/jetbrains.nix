# JetBrains IDE vim bindings. Cross-platform (bundled via desktop.nix) — ~/.ideavimrc is
# where every JetBrains IDE looks on both macOS and Linux. Routed through the shared
# sourceFile helper so it honors publicHome.dotfiles.mode like the other GUI dotfiles
# (previously a bare store path, which was store-copied even in outOfStore mode).
{ config, ... }:
{
  home.file.".ideavimrc".source = config.lib.publicHome.sourceFile "files/ideavimrc";
}
