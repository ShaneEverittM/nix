# CachyOS desktop ("hope") assembly: a standalone home-manager configuration on a
# NON-NixOS Linux distro. Applied with `nh home switch` (nh matches shane@hope).
#
# Arch/CachyOS owns the system — packages, the display manager, the login shell — and
# Nix is installed alongside it, so there is no NixOS layer here at all. That makes
# this host structurally the twin of hosts/macbook (standalone home-manager, GUI
# dotfiles, no system module), just on x86_64-linux; the only extra piece is
# generic-linux.nix, which papers over the foreign-distro/Nix-store gap.
{ inputs, system }:

let
  identity = import ../../lib/identity.nix;
  mkPkgs = import ../../lib/mk-pkgs.nix;
  pkgs = mkPkgs {
    input = inputs.nixpkgs;
    inherit system;
  };
  pkgsUnstable = mkPkgs {
    input = inputs.nixpkgs-unstable;
    inherit system;
  };
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  extraSpecialArgs = {
    inherit pkgsUnstable;
  };

  modules = [
    ../../modules/home # core bundle (common + git + onepassword + ssh + shell + rust + bun + java)
    ../../modules/home/linux.nix # shared Linux layer
    ../../modules/home/generic-linux.nix # non-NixOS distro fixups (XDG, locale, fonts)
    ../../modules/home/desktop.nix # GUI dotfiles (vscode + zed + warp + jetbrains)
    {
      # Personal git identity, single-sourced (already public). repoRoot defaults to
      # ~/.config/nix, which is also the default NH_HOME_FLAKE and out-of-store
      # dotfile root.
      publicHome.git.userName = identity.userName;
      publicHome.git.userEmail = identity.userEmail;

      # Commit signing via the 1Password SSH key (same key everywhere). The Linux
      # 1Password app (installed from the distro) ships its own signer, at a different
      # path than macOS.
      publicHome.git.signingKey = identity.sshPublicKey;
      publicHome.git.sshSigningProgram = "/opt/1Password/op-ssh-sign";

      # The Linux 1Password app exposes the agent natively; sshAuthSock already
      # defaults to the ~/.1password/agent.sock it creates. Opt-in on Linux (see
      # modules/home/onepassword.nix).
      publicHome.onepassword.sshAgent = true;

      # Warp is installed from the distro; Nix manages only its config, under the XDG
      # paths Warp uses on Linux (see modules/home/warp.nix).
      #
      # Less transparent than the Macs' 70: KDE's compositor blurs differently, so
      # the shared value washes out text here. Deep-merged over the shared
      # appearance.window block, so override_blur and zoom_level still come from it.
      programs.warp.settings.appearance.window.override_opacity = 90;
    }
  ];
}
