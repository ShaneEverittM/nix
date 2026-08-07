# NixOS desktop assembly: the `nixosConfigurations.exodus` system — NixOS with
# home-manager folded in as a module, for a bare-metal KDE desktop. Formerly a
# standalone home-manager config on CachyOS (see git history); now Nix owns the
# whole box.
#
# The home layer imports the shared core + linux.nix + desktop.nix (GUI dotfiles), but
# NOT generic-linux.nix: that module's non-NixOS fixups (XDG_DATA_DIRS, LOCALE_ARCHIVE)
# are handled natively by NixOS and would be actively wrong here.
{ inputs, system }:

let
  # Unstable lane. Feeds the shared fast-moving CLI tools (mise, acli), Zed, and Warp
  # (see home.packages below) — all fast movers that benefit from the newer channel.
  # allowUnfree matches the system's stance in the shared NixOS base; the narrow shared
  # predicate in lib/nixpkgs-config.nix only covers acli.
  pkgsUnstable = import ../../lib/mk-pkgs.nix {
    input = inputs.nixpkgs-unstable;
    inherit system;
    extraConfig.allowUnfree = true;
  };
in
inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  # Thread the flake inputs to modules (the shared base uses it for the
  # nixPath pin).
  specialArgs = { inherit inputs; };

  modules = [
    ./configuration.nix
    # Shared physical-host base bundle: boot, locale, users, sshd, tailscale, nh, and
    # the home-manager fold-in with the personal identity (see modules/nixos/).
    ../../modules/nixos
    {
      home-manager.extraSpecialArgs = { inherit pkgsUnstable; };
      home-manager.users.shane =
        {
          pkgs,
          pkgsUnstable,
          ...
        }:
        {
          imports = [
            ../../modules/home # core bundle (common + git + onepassword + ssh + shell + rust + bun + java)
            ../../modules/home/linux.nix # shared Linux layer
            ../../modules/home/desktop.nix # GUI dotfiles (vscode + zed + warp + jetbrains)
            ./cider.nix # launcher entry for the out-of-store Cider AppImage
          ];

          # Identity (name/email/signing key) comes from the shared base. The signer
          # program is host-specific: on NixOS it ships inside the Nix-built 1Password
          # GUI package rather than at CachyOS's /opt/1Password/op-ssh-sign, so point
          # at the store path.
          publicHome.git.sshSigningProgram = "${pkgs._1password-gui}/share/1password/op-ssh-sign";

          # The Linux 1Password app exposes the agent natively; sshAuthSock already
          # defaults to the ~/.1password/agent.sock it creates.
          # Enable the agent socket in 1Password → Settings → Developer on first boot.
          publicHome.onepassword.sshAgent = true;

          # Start 1Password at login, silently to the system tray, so the SSH agent is
          # already up when the session begins -- otherwise the first git push / signed
          # commit of the day fails ("could not connect to socket") until the app is
          # opened by hand. `--silent` is 1Password's own start-minimized flag (what its
          # "Start at login" setting writes). Lives here, not in the cross-platform
          # onepassword.nix, because the Nix GUI + tray autostart is specific to this
          # bare-metal desktop (the Macs use native login items).
          #
          # A native systemd user service, NOT an XDG autostart .desktop: the .desktop
          # becomes a *generated* unit with no [Service] control, and 1Password is
          # Electron -- on the SIGTERM systemd sends at logout, Chromium tends to trap
          # (signal 5) while tearing down its GPU/zygote children instead of exiting 0.
          # That crash-on-logout is what once seeded a multi-hour DrKonqi coredump loop
          # (see the crash-handling block in configuration.nix). Owning the unit lets us
          # send a gentler stop signal, bound the stop time, and treat the trap as a
          # clean exit. Ordered after plasma-workspace.target so the tray exists before
          # --silent minimizes into it. Keep 1Password's in-app "Start at login" OFF so
          # it doesn't also write the .desktop and double-start.
          systemd.user.services."1password" = {
            Unit = {
              Description = "1Password (start minimized to the system tray)";
              After = [ "plasma-workspace.target" ];
              PartOf = [ "graphical-session.target" ];
            };
            Service = {
              ExecStart = "${pkgs._1password-gui}/bin/1password --silent";
              # Chromium runs its own quit path on SIGINT but often traps on SIGTERM
              # mid-teardown; treat a trap (128+5=133) as success so a messy-but-final
              # exit isn't logged as a crash. Bound the stop so logout never waits on it.
              KillSignal = "SIGINT";
              TimeoutStopSec = 10;
              SuccessExitStatus = "SIGTRAP";
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };

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
    }
  ];
}
