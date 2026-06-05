# Rust toolchain via rustup, plus a cross-compile linker config. The cargo
# config.toml here is the sanitized public version (cross linkers + git-fetch-with-
# cli); the work machine's private Cargo registry/credential provider is overlaid in
# the private nix-work repo.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicHome.rust;
  publicCargoConfig = builtins.readFile ../../files/cargo/config.toml;
  extraCargoConfig = lib.optionalString (cfg.extraCargoConfig != "") "\n\n${cfg.extraCargoConfig}";
in
{
  options.publicHome.rust.extraCargoConfig = lib.mkOption {
    type = lib.types.lines;
    default = "";
    description = "Private Cargo config appended after the public cross-linker settings.";
  };

  config = {
    home.packages = with pkgs; [
      rustup
    ];

    home.sessionPath = [
      "$HOME/.cargo/bin"
    ];

    home.file = {
      ".cargo/config.toml".text = "${publicCargoConfig}${extraCargoConfig}";
    };
  };
}
