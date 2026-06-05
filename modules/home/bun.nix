# Bun runtime + ensure global @types/bun is installed for ad-hoc Bun scripts.
# Shared by every host.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  bunInstall = "${config.home.homeDirectory}/.bun";
  globalTypes = "${bunInstall}/install/global/node_modules/@types/bun/package.json";
in
{
  home.packages = [
    pkgs.bun
  ];

  home.sessionPath = [
    "$BUN_INSTALL/bin"
  ];

  home.sessionVariables = {
    BUN_INSTALL = bunInstall;
  };

  home.activation.ensureBunGlobalTypes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export HOME="${config.home.homeDirectory}"
    export BUN_INSTALL="${bunInstall}"

    if [ ! -e "${globalTypes}" ]; then
      echo "Installing global Bun TypeScript types..."
      $DRY_RUN_CMD mkdir -p "$BUN_INSTALL/install/global"
      $DRY_RUN_CMD ${pkgs.bun}/bin/bun install -g @types/bun
    fi
  '';
}
