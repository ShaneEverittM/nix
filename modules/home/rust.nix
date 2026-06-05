# Rust toolchain via rustup, plus generated Cargo config. The public config is
# sanitized (cross linkers + git-fetch-with-cli); private consumers can merge in
# registries/credential providers through publicHome.rust.extraCargoConfig.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicHome.rust;
  cargoToml = pkgs.formats.toml { };
  publicCargoConfig = {
    target = {
      "x86_64-unknown-linux-gnu".linker = "x86_64-linux-gnu-gcc";
      "aarch64-unknown-linux-gnu".linker = "aarch64-linux-gnu-gcc";
      "armv7-unknown-linux-gnueabihf".linker = "armv7-linux-gnueabihf-gcc";
      "aarch64-unknown-linux-musl".linker = "aarch64-linux-musl-gcc";
    };

    net."git-fetch-with-cli" = true;
  };
  cargoConfig = lib.recursiveUpdate publicCargoConfig cfg.extraCargoConfig;
in
{
  options.publicHome.rust.extraCargoConfig = lib.mkOption {
    type = lib.types.attrs;
    default = { };
    description = "Private Cargo config attrs merged after the public cross-linker settings.";
  };

  config = {
    home.packages = with pkgs; [
      rustup
    ];

    home.sessionPath = [
      "$HOME/.cargo/bin"
    ];

    home.file = {
      ".cargo/config.toml".source = cargoToml.generate "cargo-config.toml" cargoConfig;
    };
  };
}
