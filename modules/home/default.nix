# The universal home-manager core, imported by every host (WSL, personal Mac, work
# Mac). Platform-specific layers are imported alongside this: ./linux.nix on WSL,
# ./darwin.nix on the Macs. Exposed as `homeModules.default` in flake.nix.
{ ... }:
{
  imports = [
    ./common.nix # publicHome.* options, packages, stateVersion
    ./git.nix # option-driven git (identity supplied per-host)
    ./shell.nix # zsh + ergonomics
    ./rust.nix # rustup + cargo
    ./bun.nix # bun runtime
  ];
}
