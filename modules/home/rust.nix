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
  # These linker names are *cross* toolchains (Debian/Homebrew-style prefixes). The
  # host's own triple must not be pinned to one: a native build should fall through
  # to rustc's default `cc`, and nixpkgs' gcc has no `x86_64-linux-gnu-gcc` anyway
  # (its prefix is `x86_64-unknown-linux-gnu-`), so the pin breaks every native build.
  crossLinkers = removeAttrs {
    "x86_64-unknown-linux-gnu".linker = "x86_64-linux-gnu-gcc";
    "aarch64-unknown-linux-gnu".linker = "aarch64-linux-gnu-gcc";
    "armv7-unknown-linux-gnueabihf".linker = "armv7-linux-gnueabihf-gcc";
    "aarch64-unknown-linux-musl".linker = "aarch64-linux-musl-gcc";
  } [ pkgs.stdenv.hostPlatform.rust.rustcTarget ];
  publicCargoConfig = {
    target = crossLinkers;

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
    # rustup ships rustc/cargo but no linker: rustc drives the system `cc`. macOS
    # gets that from the Xcode command line tools; a Linux host has none unless we
    # install one, and it has to be on the profile PATH (not a dev shell) so that
    # non-interactive consumers like a JetBrains remote backend see it too.
    home.packages = [
      pkgs.rustup
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.gcc ];

    home.sessionPath = [
      "$HOME/.cargo/bin"
    ];

    home.file = {
      ".cargo/config.toml".source = cargoToml.generate "cargo-config.toml" cargoConfig;
    };
  };
}
