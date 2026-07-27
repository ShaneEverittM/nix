# CachyOS desktop ("exodus") assembly: a standalone home-manager configuration on a
# NON-NixOS Linux distro. Applied with `nh home switch` (nh matches shane@exodus).
#
# Arch/CachyOS owns the system — packages, the display manager, the login shell — and
# Determinate Nix is installed alongside it, so there is no NixOS layer here at all.
# That makes this host structurally the twin of hosts/macbook (standalone home-manager,
# GUI dotfiles, no system module), just on x86_64-linux; the only extra piece is
# generic-linux.nix, which papers over the foreign-distro/Nix-store gap.
{ inputs, system }:

let
  nixpkgsConfig = import ../../lib/nixpkgs-config.nix { lib = inputs.nixpkgs.lib; };
  pkgs = import inputs.nixpkgs {
    inherit system;
    config = nixpkgsConfig;
  };
  pkgsUnstable = import inputs.nixpkgs-unstable {
    inherit system;
    config = nixpkgsConfig;
  };
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  extraSpecialArgs = {
    inherit pkgsUnstable;
  };

  modules = [
    ../../modules/home # core bundle (common + git + shell + rust + bun + java)
    ../../modules/home/linux.nix # shared Linux layer (no Windows/WSL bits)
    ../../modules/home/generic-linux.nix # non-NixOS distro fixups (XDG, locale, fonts)
    ../../modules/home/desktop.nix # GUI dotfiles (vscode + zed + warp + jetbrains)
    {
      # Personal git identity (already public). repoRoot defaults to ~/.config/nix,
      # which is also the default NH_HOME_FLAKE and out-of-store dotfile root.
      publicHome.git.userName = "Shane Murphy";
      publicHome.git.userEmail = "mail@semurphy.com";

      # Commit signing via the 1Password SSH key (same key as WSL and the Mac). The
      # Linux 1Password app ships its own signer, at a different path than macOS.
      publicHome.git.signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwRBMnr95gqzkvJHmNDCprKK2QcV2vNQVS6mAsGzcz3";
      publicHome.git.sshSigningProgram = "/opt/1Password/op-ssh-sign";

      # The Linux 1Password app exposes the agent natively (no WSL-style relay needed);
      # sshAuthSock already defaults to the ~/.1password/agent.sock it creates.
      publicHome.onepassword.sshAgent = true;

      # Warp is installed from the distro; Nix manages only its config, under the XDG
      # paths Warp uses on Linux (see modules/home/warp.nix).
      programs.warp.settings = {
        # Warp renders through XWayland here; the native Wayland path is not reliable
        # on this KDE/Wayland session. Linux-only, so it stays a host override rather
        # than going into the shared profile.
        system.force_x11 = true;

        # Less transparent than the Macs' 70: KDE's compositor blurs differently, so
        # the shared value washes out text here. Deep-merged over the shared
        # appearance.window block, so override_blur and zoom_level still come from it.
        appearance.window.override_opacity = 90;
      };
    }
  ];
}
