# Push Warp config to the Windows-side Warp install from WSL.
#
# WSL-only and opt-in (publicHome.warp.wslConfig), imported via linux.nix and gated
# by the enable option — exactly like ssh-agent.nix. Warp here is a *Windows* app, so:
#
#   * It can't follow WSL/nix-store symlinks, which rules out the home.file mechanism
#     the macOS warp.nix uses. We copy real file content onto the Windows filesystem
#     (/mnt/c) in an activation step instead — declarative content, imperative
#     placement, refreshed on every `nixos-rebuild switch`.
#   * Its config lives under the Windows roaming/local profile, not ~/.warp:
#       settings -> %LOCALAPPDATA%\warp\Warp\config\settings.toml
#       themes   -> %APPDATA%\warp\Warp\data\themes\*.yaml
#   * Theme paths baked into settings.toml must be Windows paths Warp understands;
#     we use forward slashes (C:/Users/...) to avoid TOML backslash-escaping.
#
# Warp owns settings.toml at runtime (it rewrites on any UI change), so this is a
# seed-on-switch, not a locked file — the same trade-off the macOS module accepts.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicHome.warp;
  warpToml = pkgs.formats.toml { };
  mkSettings = import ./warp-settings.nix { inherit lib; };

  # Windows-side roots, split between Roaming (%APPDATA%) and Local (%LOCALAPPDATA%).
  winThemesDir = "C:/Users/${cfg.windowsUser}/AppData/Roaming/warp/Warp/data/themes";
  wslThemesDir = "/mnt/c/Users/${cfg.windowsUser}/AppData/Roaming/warp/Warp/data/themes";
  wslSettingsPath = "/mnt/c/Users/${cfg.windowsUser}/AppData/Local/warp/Warp/config/settings.toml";

  settingsFile = warpToml.generate "warp-wsl-settings.toml" (mkSettings {
    themeDir = winThemesDir;
    overrides = cfg.extraSettings;
  });

  darkTheme = ../../files/warp/themes/jetbrains-ide-dark.yaml;
  lightTheme = ../../files/warp/themes/jetbrains-ide-light.yaml;

  install = "${pkgs.coreutils}/bin/install";
in
{
  options.publicHome.warp = {
    wslConfig = lib.mkEnableOption "seeding the Windows-side Warp install (settings + themes) from WSL";

    windowsUser = lib.mkOption {
      type = lib.types.str;
      default = config.publicHome.username;
      description = "Windows user name owning the Warp profile under /mnt/c/Users.";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Warp settings attrs deep-merged over the shared defaults before TOML generation.";
    };
  };

  config = lib.mkIf cfg.wslConfig {
    # Guard on the Windows user dir so a bad windowsUser (or a non-WSL Linux host
    # that somehow flipped this on) can't fail the switch or create junk dirs.
    home.activation.warpWindowsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -d "/mnt/c/Users/${cfg.windowsUser}" ]; then
        $DRY_RUN_CMD ${install} $VERBOSE_ARG -D -m0644 ${settingsFile} "${wslSettingsPath}"
        $DRY_RUN_CMD ${install} $VERBOSE_ARG -D -m0644 ${darkTheme} "${wslThemesDir}/jetbrains-ide-dark.yaml"
        $DRY_RUN_CMD ${install} $VERBOSE_ARG -D -m0644 ${lightTheme} "${wslThemesDir}/jetbrains-ide-light.yaml"
      else
        echo "warp-wsl: /mnt/c/Users/${cfg.windowsUser} not found; skipping Windows Warp seed" >&2
      fi
    '';
  };
}
