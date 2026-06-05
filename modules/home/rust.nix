# Rust toolchain via rustup, plus a cross-compile linker config. The cargo
# config.toml here is the sanitized public version (cross linkers + git-fetch-with-
# cli); the work machine's private Cargo registry/credential provider is overlaid in
# the private nix-work repo.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    rustup
  ];

  home.sessionPath = [
    "$HOME/.cargo/bin"
  ];

  home.file = {
    ".cargo/config.toml".source = ../../files/cargo/config.toml;
  };
}
