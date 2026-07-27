# JetBrains IDE vim bindings. Cross-platform (bundled via desktop.nix) — ~/.ideavimrc is
# where every JetBrains IDE looks on both macOS and Linux.
{
  home.file = {
    ".ideavimrc".source = ../../files/ideavimrc;
  };
}
