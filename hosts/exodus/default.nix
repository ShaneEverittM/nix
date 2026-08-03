# NixOS desktop assembly: the `nixosConfigurations.exodus` system. Structurally the
# twin of hosts/wsl/default.nix — a NixOS system with home-manager folded in as a
# module — but for a bare-metal KDE desktop instead of WSL. Formerly a standalone
# home-manager config on CachyOS (see git history); now Nix owns the whole box.
#
# The home layer imports the shared core + linux.nix + desktop.nix (GUI dotfiles), but
# NOT generic-linux.nix: that module's non-NixOS fixups (XDG_DATA_DIRS, LOCALE_ARCHIVE)
# are handled natively by NixOS and would be actively wrong here.
{ inputs, system }:

let
  nixpkgsConfig = import ../../lib/nixpkgs-config.nix { lib = inputs.nixpkgs.lib; };
  # Unstable lane. Feeds the shared fast-moving CLI tools (mise, acli), Zed, and Warp
  # (see home.packages below) — all fast movers that benefit from the newer channel.
  # allowUnfree matches the system's stance in ./configuration.nix; the narrow shared
  # predicate in lib/nixpkgs-config.nix only covers acli.
  pkgsUnstable = import inputs.nixpkgs-unstable {
    inherit system;
    config = nixpkgsConfig // {
      allowUnfree = true;
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  # Thread the flake inputs to modules (modules/nixos/common.nix uses it for the
  # nixPath pin).
  specialArgs = { inherit inputs; };

  modules = [
    inputs.home-manager.nixosModules.home-manager
    ./configuration.nix
    ../../modules/nixos/common.nix
    {
      home-manager.extraSpecialArgs = { inherit pkgsUnstable; };
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.shane =
        {
          pkgs,
          pkgsUnstable,
          ...
        }:
        {
          imports = [
            ../../modules/home # core bundle (common + git + shell + rust + bun)
            ../../modules/home/linux.nix # shared Linux layer (no Windows/WSL bits)
            ../../modules/home/desktop.nix # GUI dotfiles (vscode + zed + warp + jetbrains)
            ./cider.nix # launcher entry for the out-of-store Cider AppImage
          ];

          # Personal git identity (already public). The work Mac sets its own in the
          # private nix-work repo.
          publicHome.git.userName = "Shane Murphy";
          publicHome.git.userEmail = "mail@semurphy.com";

          # Commit signing via the 1Password SSH key (same key as WSL and the Mac). On
          # NixOS the signer ships inside the Nix-built 1Password GUI package rather than
          # at CachyOS's /opt/1Password/op-ssh-sign, so point at the store path.
          publicHome.git.signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwRBMnr95gqzkvJHmNDCprKK2QcV2vNQVS6mAsGzcz3";
          publicHome.git.sshSigningProgram = "${pkgs._1password-gui}/share/1password/op-ssh-sign";

          # The Linux 1Password app exposes the agent natively (no WSL-style relay);
          # sshAuthSock already defaults to the ~/.1password/agent.sock it creates.
          # Enable the agent socket in 1Password → Settings → Developer on first boot.
          publicHome.onepassword.sshAgent = true;

          # Start 1Password at login, silently to the system tray, so the SSH agent is
          # already up when the session begins -- otherwise the first git push / signed
          # commit of the day fails ("could not connect to socket") until the app is
          # opened by hand. `--silent` is 1Password's own start-minimized flag (what its
          # "Start at login" setting writes); the XDG autostart entry is read by the KDE
          # session. Lives here, not in the cross-platform onepassword.nix, because the
          # Nix-built GUI + tray autostart is specific to this bare-metal desktop (WSL
          # relays the agent from Windows; the Macs use native login items).
          xdg.configFile."autostart/1password.desktop".text = ''
            [Desktop Entry]
            Type=Application
            Name=1Password
            Icon=1password
            Exec=${pkgs._1password-gui}/bin/1password --silent
            Terminal=false
            X-GNOME-Autostart-enabled=true
          '';

          # Warp is installed from Nix here (see home.packages below); this module still
          # only owns its config, under the XDG paths Warp uses on Linux.
          programs.warp.settings = {
            # Native Wayland, not XWayland. Needs BOTH fixes below to hold: the
            # waylandSupport override on the package (adds libwayland-client to the
            # autoPatchelf runtime path so winit can dlopen it, and sets
            # WARP_ENABLE_WAYLAND=1) and the VK_DRIVER_FILES pin (so wgpu renders on the
            # NVIDIA card, not the AMD iGPU that can't present to the NVIDIA-owned
            # surface). Without either, Warp crashes on startup and rewrites this key
            # back to true at runtime.
            system.force_x11 = false;

            # Less transparent than the Macs' 70: KDE's compositor blurs differently, so
            # the shared value washes out text here. Deep-merged over the shared
            # appearance.window block, so override_blur and zoom_level still come from it.
            appearance.window.override_opacity = 90;
          };

          # Pin the Vulkan loader to the NVIDIA ICD. wgpu (Warp's renderer) enumerates
          # both GPUs and picks the AMD iGPU, which can't present to a Wayland surface on
          # the NVIDIA-driven outputs — Warp then crashes on startup and disables Wayland.
          # The iGPU drives no display on this box, so pinning *every* Vulkan app to the
          # NVIDIA card is exactly what we want. Both arch ICDs are listed (64- then
          # 32-bit) so 32-bit Vulkan — Steam/Proton — still resolves; the loader uses the
          # arch-matching entry.
          #
          # systemd.user.sessionVariables (→ ~/.config/environment.d), not
          # home.sessionVariables: the failing path is launching from the KDE launcher,
          # which never sources hm-session-vars.sh. environment.d *is* read by the
          # graphical session (and shells it spawns). Takes effect on next login.
          systemd.user.sessionVariables.VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json:/run/opengl-driver-32/share/vulkan/icd.d/nvidia_icd.json";

          # Desktop apps that came from the CachyOS distro before this migration now come
          # from Nix (Nix already owns their config via desktop.nix). Warp and Zed track
          # the nixpkgs-unstable lane because they move fast. Warp's Linux build is a
          # plain autoPatchelf package (no bwrap/FHS wrapper), so setuid tools — sudo, nh's
          # elevation, ssh's config-ownership check — work normally in its panes. The
          # waylandSupport override adds libwayland-client for the native-Wayland path
          # (see programs.warp.settings above). Tradeoff vs the old AppImage pin: a store
          # build can't self-update, so Warp nags when the channel lags upstream. The rest
          # stay on stable. JetBrains defaults to IDEA Ultimate (jetbrains.idea); swap the
          # attr (e.g. jetbrains.rust-rover).
          home.packages =
            (with pkgs; [
              vscode
              jetbrains.idea
              claude-code
              discord
            ])
            ++ [
              (pkgsUnstable.warp-terminal.override { waylandSupport = true; })
              pkgsUnstable.zed-editor
            ];
        };

      # Enable the NixOS-side nh so `nh os switch`/`nh os boot` work without a flake
      # path. NH_OS_FLAKE mirrors the home side's NH_HOME_FLAKE: both point at this
      # repo's checkout (publicHome.repoRoot defaults to ~/.config/nix).
      programs.nh = {
        enable = true;
        flake = "/home/shane/.config/nix";
      };
    }
  ];
}
