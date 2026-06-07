# Warp terminal settings, keybindings, and themes (mirrored
# to both the stable `.warp` and OSS `.warp-oss` profile dirs). Mac-only (bundled via
# darwin.nix). The optional packageSource installs a Warp build through Home Manager;
# leave it "none" unless a `warpPackages` arg is supplied by the consumer.
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
  # macOS keeps custom themes under each profile dir; theme paths are baked into
  # the generated settings.toml so Warp can resolve them.
  settingsFor =
    profileDir:
    mkSettings {
      themeDir = "${config.publicHome.homeDirectory}/${profileDir}/themes";
      overrides = cfg.settings;
    };
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

    home.file = {
      ".warp/settings.toml" = {
        source = warpToml.generate "warp-settings.toml" (settingsFor ".warp");
        force = true;
      };

      ".warp/keybindings.yaml" = {
        source = sourceFile "files/warp/keybindings.yaml";
        force = true;
      };

      ".warp-oss/settings.toml" = {
        source = warpToml.generate "warp-oss-settings.toml" (settingsFor ".warp-oss");
        force = true;
      };

      ".warp-oss/keybindings.yaml" = {
        source = sourceFile "files/warp/keybindings.yaml";
        force = true;
      };

      ".warp/themes/jetbrains-ide-dark.yaml" = {
        source = sourceFile "files/warp/themes/jetbrains-ide-dark.yaml";
        force = true;
      };

      ".warp/themes/jetbrains-ide-light.yaml" = {
        source = sourceFile "files/warp/themes/jetbrains-ide-light.yaml";
        force = true;
      };

      ".warp-oss/themes/jetbrains-ide-dark.yaml" = {
        source = sourceFile "files/warp/themes/jetbrains-ide-dark.yaml";
        force = true;
      };

      ".warp-oss/themes/jetbrains-ide-light.yaml" = {
        source = sourceFile "files/warp/themes/jetbrains-ide-light.yaml";
        force = true;
      };
    };
  };
}
