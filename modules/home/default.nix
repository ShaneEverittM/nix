# The universal home-manager core, imported by the workstation hosts (exodus, personal
# Mac, work Mac). Platform-specific layers are imported alongside this: ./linux.nix
# (+ ./desktop.nix) on native Linux, ./darwin.nix on the Macs. Exposed as
# `homeModules.default` in flake.nix. (The rebirth server skips the bundle and imports
# ./git.nix + ./shell.nix à la carte.)
{ ... }:
{
  imports = [
    ./common.nix # publicHome.* options, packages, stateVersion
    ./git.nix # option-driven git (identity supplied per-host)
    ./onepassword.nix # SSH_AUTH_SOCK for the 1Password agent (per-platform path)
    ./ssh.nix # ~/.ssh/config: host aliases for this repo's machines
    ./shell.nix # zsh + ergonomics
    ./rust.nix # rustup + cargo
    ./bun.nix # bun runtime
    ./java.nix # jdk (LTS) + stable JAVA_HOME symlink for gradle/JetBrains
  ];
}
