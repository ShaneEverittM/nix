# Warp terminal settings, keybindings, and themes. Cross-platform (bundled via
# ./desktop.nix): Warp's config layout differs per OS, but the settings *schema* does
# not, so all platforms share one profile from ./warp-settings.nix.
#
#   macOS   settings ~/.warp/settings.toml          themes ~/.warp/themes
#           (mirrored to the OSS profile dir ~/.warp-oss/* as well)
#   Linux   settings ~/.config/warp-terminal/settings.toml
#           themes   ~/.local/share/warp-terminal/themes
#
# WSL is NOT covered here — Warp there is a Windows app that can't follow store
# symlinks; see ./warp-wsl.nix, the third consumer of the shared settings schema.
#
# The optional packageSource installs a Warp build through Home Manager; leave it "none"
# unless a `warpPackages` arg is supplied by the consumer. On the public hosts Warp comes
# from Homebrew (macOS) or the distro (Linux), and Nix owns only its config.
{
  config,
  lib,
  pkgs,
  warpPackages ? { },
  ...
}:

let
  cfg = config.programs.warp;
  publicRoot = ../..;
  warpToml = pkgs.formats.toml { };
  sourceFile =
    path:
    if config.publicHome.dotfiles.mode == "outOfStore" then
      config.lib.file.mkOutOfStoreSymlink "${toString config.publicHome.repoRoot}/${path}"
    else
      publicRoot + "/${path}";
  mkSettings = import ./warp-settings.nix { inherit lib; };

  themeNames = [
    "jetbrains-ide-dark"
    "jetbrains-ide-light"
  ];

  # One entry per config tree Warp reads on this OS. `name` only names the generated
  # store path; the three dirs are home-relative.
  profiles =
    if pkgs.stdenv.isDarwin then
      [
        {
          name = "stable";
          configDir = ".warp";
          themeDir = ".warp/themes";
        }
        {
          name = "oss";
          configDir = ".warp-oss";
          themeDir = ".warp-oss/themes";
        }
      ]
    else
      [
        {
          name = "linux";
          configDir = ".config/warp-terminal";
          themeDir = ".local/share/warp-terminal/themes";
        }
      ];

  # Theme paths are baked into settings.toml (Warp resolves them itself, so they must be
  # absolute and profile-local), which is why settings are generated per profile rather
  # than once and reused.
  profileFiles =
    profile:
    {
      "${profile.configDir}/settings.toml" = {
        source = warpToml.generate "warp-${profile.name}-settings.toml" (mkSettings {
          themeDir = "${config.publicHome.homeDirectory}/${profile.themeDir}";
          overrides = cfg.settings;
        });
        force = true;
      };

      "${profile.configDir}/keybindings.yaml" = {
        source = sourceFile "files/warp/keybindings.yaml";
        force = true;
      };
    }
    // lib.listToAttrs (
      map (
        theme:
        lib.nameValuePair "${profile.themeDir}/${theme}.yaml" {
          source = sourceFile "files/warp/themes/${theme}.yaml";
          force = true;
        }
      ) themeNames
    );
in
{
  options.programs.warp = {
    packageSource = lib.mkOption {
      type = lib.types.enum [
        "none"
        "stable"
        "local-oss"
      ];
      default = "none";
      description = "Warp package source to install through Home Manager.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Warp settings attrs merged with the public defaults before TOML generation.";
    };
  };

  config = {
    home.packages = lib.optional (cfg.packageSource != "none") warpPackages.${cfg.packageSource};

    # Each `nh home switch` rebuilds the .app at a fresh /nix/store path, but macOS
    # keeps the icon keyed to the old path, so Finder/Dock fall back to a generic
    # folder until the app runs (the running app sets its own Dock icon directly).
    # Re-register the bundle with LaunchServices after linking to refresh the icon.
    home.activation = lib.mkIf (pkgs.stdenv.isDarwin && cfg.packageSource != "none") {
      registerWarpOss = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        app="${config.home.homeDirectory}/Applications/Home Manager Apps/WarpOss.app"
        lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        if [ -d "$app" ] && [ -x "$lsregister" ]; then
          run "$lsregister" -f "$app"
        fi
      '';
    };

    home.file = lib.mkMerge (map profileFiles profiles);
  };
}
