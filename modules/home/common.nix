# Platform-agnostic home-manager config, shared by every host (WSL, personal Mac,
# work Mac). Anything here must hold on both Linux and Darwin — OS-specific bits live
# in ./linux.nix and ./darwin.nix.
#
# This module owns the `publicHome.*` option namespace: the shared modules carry
# behavior, each host (and the downstream private work repo) supplies the values
# (username, git identity, where the repo is checked out).
#
# NOTE: keep this module free of any `nix.*` settings. The work Mac runs Determinate
# Nix (which owns Nix's own config) and consumes this module via standalone
# home-manager; managing Nix here would fight Determinate. All nix.settings/nixPath
# live in modules/nixos/* instead, which only the WSL host imports.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicHome;
in
{
  options.publicHome = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "shane";
      description = "Login user name; also derives home.homeDirectory.";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = if pkgs.stdenv.isDarwin then "/Users/${cfg.username}" else "/home/${cfg.username}";
      description = "Home directory. Defaults to the platform-standard path for username.";
    };

    configRoot = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.homeDirectory}/.config/home-manager";
      description = ''
        Where this repo is checked out on the target machine. Used by the
        out-of-store symlinks in vscode.nix/warp.nix (so the dotfiles stay live-
        editable) and the `hm` shell alias. Macs run the hm.ts workflow from here;
        WSL leaves the default since those modules are not imported there.
      '';
    };
  };

  config = {
    home.username = cfg.username;
    home.homeDirectory = cfg.homeDirectory;
    home.stateVersion = "25.11";

    programs.home-manager.enable = true;
    news.display = "silent";

    # mkAfter keeps ~/.local/bin last in PATH — host modules (e.g. linux.nix's VS
    # Code dir) take precedence.
    home.sessionPath = lib.mkAfter [
      "${cfg.homeDirectory}/.local/bin"
    ];

    # The cross-host shared package set (see lib/packages.nix).
    home.packages = import ../../lib/packages.nix pkgs;
  };
}
