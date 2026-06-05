# Platform-agnostic home-manager config, shared by every host (WSL, personal Mac,
# work Mac). Anything here must hold on both Linux and Darwin — OS-specific bits live
# in ./linux.nix and ./darwin.nix.
#
# This module owns the `publicHome.*` option namespace: the shared modules carry
# behavior, each host (and the downstream private work repo) supplies the values
# (username, git identity, repo paths, dotfile mode, and private overlays).
#
# NOTE: keep this module free of any `nix.*` settings. The work Mac runs Determinate
# Nix (which owns Nix's own config) and consumes this module via standalone
# home-manager; managing Nix here would fight Determinate. All nix.settings/nixPath
# live in modules/nixos/* instead, which only the WSL host imports.
{
  config,
  lib,
  pkgs,
  pkgsUnstable ? pkgs,
  ...
}:

let
  cfg = config.publicHome;
  nhHomeFlake = toString cfg.nh.homeFlake;
  nhHomeInstallable =
    if cfg.nh.homeConfiguration == null then
      nhHomeFlake
    else
      "${nhHomeFlake}#${cfg.nh.homeConfiguration}";
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

    repoRoot = lib.mkOption {
      type = lib.types.oneOf [
        lib.types.str
        lib.types.path
      ];
      default = "${cfg.homeDirectory}/.config/nix";
      description = ''
        Where this public repo is checked out on the target machine. Public hosts
        use it for live-editable dotfiles and the default hm helper.
      '';
    };

    dotfiles.mode = lib.mkOption {
      type = lib.types.enum [
        "store"
        "outOfStore"
      ];
      default = "outOfStore";
      description = "Whether public dotfiles are copied from the flake store or linked live from publicHome.repoRoot.";
    };

    nh.homeFlake = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.oneOf [
          lib.types.str
          lib.types.path
        ]
      );
      default = cfg.repoRoot;
      description = ''
        Flake path exported as NH_HOME_FLAKE for nh home commands. Public hosts
        usually use publicHome.repoRoot; downstream private overlays should set
        this to their own consuming flake root.
      '';
    };

    nh.homeConfiguration = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional homeConfigurations attribute name appended to NH_HOME_FLAKE.
        This lets nh home commands default to a non-hostname-derived config name.
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

    # The cross-host shared package set: mostly stable, with a small explicit
    # unstable lane for fast-moving tools (see lib/unstable-packages.nix).
    home.packages =
      import ../../lib/packages.nix pkgs ++ import ../../lib/unstable-packages.nix pkgsUnstable;

    programs.nh = {
      enable = true;
    }
    // lib.optionalAttrs (cfg.nh.homeFlake != null) {
      homeFlake = nhHomeInstallable;
    };
  };
}
