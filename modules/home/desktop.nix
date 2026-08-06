# Cross-platform desktop/GUI dotfile bundle: the editor, terminal, and IDE config that
# any machine with a graphical session wants, regardless of OS. Imported by ./darwin.nix
# (both Macs) and directly by native Linux desktop hosts.
#
# Every module below resolves its own per-OS paths (see e.g. the layout tables in
# ./vscode.nix and ./warp.nix), so this bundle carries no platform conditionals itself.
# It deliberately does NOT install the apps — they come from Homebrew on macOS and the
# distro on Linux; Nix only owns their config. Writing config for an app that isn't
# installed yet is harmless and means it is already right when the app arrives.
#
# Not for headless hosts: with no graphical session the config dirs would be inert.
{ ... }:
{
  imports = [
    ./vscode.nix
    ./zed.nix
    ./warp.nix
    ./jetbrains.nix
  ];
}
