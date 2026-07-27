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

      # Dual-GPU box: displays hang off the NVIDIA card, but both GPUs expose Vulkan and
      # wgpu ranks the AMD iGPU first. An app that picks the iGPU then can't present to
      # a Wayland surface owned by the NVIDIA-driven output — the queue family doesn't
      # support it — and dies with ERROR_SURFACE_LOST_KHR. (Warp did exactly this until
      # force_x11 was turned off; XWayland had been hiding it.) Pin the Vulkan loader to
      # the NVIDIA ICD.
      #
      # systemd.user.sessionVariables, not home.sessionVariables: the broken case is
      # launching from the KDE launcher, which never sources hm-session-vars.sh. This
      # lands in ~/.config/environment.d instead, which the graphical session does read
      # (and which shells started from that session inherit). Takes effect on next login.
      #
      # NOTE: session-wide, so this pins *every* Vulkan app to the NVIDIA card. If
      # something should render on the iGPU instead, scope this to Warp via a
      # desktop-entry override rather than widening the exception here.
      systemd.user.sessionVariables.VK_DRIVER_FILES = "/usr/share/vulkan/icd.d/nvidia_icd.json";

      # Warp is installed from the distro; Nix manages only its config, under the XDG
      # paths Warp uses on Linux (see modules/home/warp.nix).
      programs.warp.settings = {
        # Native Wayland, not XWayland. Kept explicit (rather than just omitted) because
        # this was true until the VK_DRIVER_FILES pin above: without it Warp picked the
        # iGPU, failed to present, and force_x11 was the only way to get a window at all.
        # Linux-only, so it stays a host override rather than going into the shared
        # profile.
        system.force_x11 = false;

        # Less transparent than the Macs' 70: KDE's compositor blurs differently, so
        # the shared value washes out text here. Deep-merged over the shared
        # appearance.window block, so override_blur and zoom_level still come from it.
        appearance.window.override_opacity = 90;
      };
    }
  ];
}
