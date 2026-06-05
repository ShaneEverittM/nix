# Warp terminal settings, keybindings, and themes as out-of-store symlinks (mirrored
# to both the stable `.warp` and OSS `.warp-oss` profile dirs). Mac-only (bundled via
# darwin.nix). The optional packageSource installs a Warp build through Home Manager;
# leave it "none" unless a `warpPackages` arg is supplied by the consumer.
{
  config,
  lib,
  warpPackages ? { },
  ...
}:

let
  cfg = config.programs.warp;
  configRoot = config.publicHome.configRoot;
  link = path: config.lib.file.mkOutOfStoreSymlink "${configRoot}/${path}";
in
{
  options.programs.warp.packageSource = lib.mkOption {
    type = lib.types.enum [
      "none"
      "stable"
      "local-oss"
    ];
    default = "none";
    description = "Warp package source to install through Home Manager.";
  };

  config = {
    home.packages = lib.optional (cfg.packageSource != "none") warpPackages.${cfg.packageSource};

    home.file = {
      ".warp/settings.toml" = {
        source = link "files/warp/warp.toml";
        force = true;
      };

      ".warp/keybindings.yaml" = {
        source = link "files/warp/keybindings.yaml";
        force = true;
      };

      ".warp-oss/settings.toml" = {
        source = link "files/warp/warp.toml";
        force = true;
      };

      ".warp-oss/keybindings.yaml" = {
        source = link "files/warp/keybindings.yaml";
        force = true;
      };

      ".warp/themes/jetbrains-ide-dark.yaml" = {
        source = link "files/warp/themes/jetbrains-ide-dark.yaml";
        force = true;
      };

      ".warp/themes/jetbrains-ide-light.yaml" = {
        source = link "files/warp/themes/jetbrains-ide-light.yaml";
        force = true;
      };

      ".warp-oss/themes/jetbrains-ide-dark.yaml" = {
        source = link "files/warp/themes/jetbrains-ide-dark.yaml";
        force = true;
      };

      ".warp-oss/themes/jetbrains-ide-light.yaml" = {
        source = link "files/warp/themes/jetbrains-ide-light.yaml";
        force = true;
      };
    };
  };
}
