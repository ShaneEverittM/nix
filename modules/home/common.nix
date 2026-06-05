# Platform-agnostic home-manager config, shared by every host (WSL, personal Mac,
# work Mac). Anything here must hold on both Linux and Darwin — OS-specific bits live
# in ./linux.nix and ./darwin.nix, which set home.homeDirectory and add host-only paths.
#
# NOTE: keep this module free of any `nix.*` settings. The work Mac runs Determinate
# Nix (which owns Nix's own config) and consumes this module via standalone
# home-manager; managing Nix here would fight Determinate. All nix.settings/nixPath
# live in modules/nixos/* instead, which only the WSL host imports.
{ config, lib, pkgs, ... }:
{
  home.username = "shane";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # Let home-manager manage bash. This is what sources hm-session-vars.sh (and
  # thus applies home.sessionPath below) — without an HM-managed shell, those
  # session vars are written but never sourced. (This is unrelated to the
  # earlier reverted set-environment hack; it adds no bashrcExtra.)
  programs.bash.enable = true;

  # mkAfter keeps ~/.local/bin last in PATH — host modules (e.g. linux.nix's VS Code
  # dir) take precedence, matching the original ordering before this split.
  home.sessionPath = lib.mkAfter [
    "${config.home.homeDirectory}/.local/bin"
  ];

  # git lives here so its identity is declarative (replaces a hand-edited
  # ~/.gitconfig). Uncomment and fill in your details, then rebuild.
  programs.git = {
    enable = true;
    settings.user.name = "Shane Murphy";
    settings.user.email = "mail@shanemurphy.space";
    settings.init.defaultBranch = "main";
  };

  # The cross-host shared package set (see lib/packages.nix).
  home.packages = import ../../lib/packages.nix pkgs;
}
