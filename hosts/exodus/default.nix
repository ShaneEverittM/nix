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
  # Unstable lane. Feeds the shared fast-moving CLI tools (mise, acli) and Zed (see
  # home.packages below). Warp no longer rides this lane — it's pinned to the upstream
  # AppImage instead (see warp-terminal-appimage). allowUnfree matches the system's
  # stance in ./configuration.nix; the narrow shared predicate in
  # lib/nixpkgs-config.nix only covers acli.
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
        let
          # Warp ships fast-moving releases and a store-installed build can't self-update
          # (read-only store) — so instead of tracking nixpkgs we pin the upstream Linux
          # AppImage directly and run it via appimageTools. To bump, resolve the current
          # versioned URL and hash, then update warpVersion + src.hash below:
          #   url=$(curl -sL -o /dev/null -w '%{url_effective}' \
          #         'https://app.warp.dev/download?package=appimage')
          #   nix-prefetch-url "$url" | xargs nix hash convert --hash-algo sha256
          warpVersion = "0.2026.07.29.09.05.stable_02";
          warpSrc = pkgs.fetchurl {
            url = "https://releases.warp.dev/stable/v${warpVersion}/Warp-x86_64.AppImage";
            hash = "sha256-wuyM3GcAG6vK/GU5MECVxHhcY7fXoXhZNE3jIltAVBE=";
          };
          # The bundled .desktop + icon tree, extracted so we can install them ourselves —
          # wrapType2 wraps only the binary and ships no launcher entry or icon.
          warpAppimageContents = pkgs.appimageTools.extractType2 {
            pname = "warp-terminal";
            version = warpVersion;
            src = warpSrc;
          };
          # winit dlopens libwayland-client.so.0 (and libxkbcommon) at runtime. Where the
          # old prebuilt-binary build needed an LD_LIBRARY_PATH wrap, appimageTools runs
          # Warp inside an FHS env, so we just add those libs to it. Native Wayland still
          # depends on the two runtime knobs set on the home config below
          # (system.force_x11 = false and the VK_DRIVER_FILES NVIDIA pin); this only
          # makes the Wayland libs loadable in the first place. The FHS env also
          # ro-binds /run/opengl-driver, so the Vulkan ICD pin resolves inside it.
          warp-terminal-appimage = pkgs.appimageTools.wrapType2 {
            pname = "warp-terminal";
            version = warpVersion;
            src = warpSrc;

            extraPkgs = _: [
              pkgs.wayland
              pkgs.libxkbcommon
            ];

            # wrapType2 names the binary $out/bin/warp-terminal (= pname), preserving the
            # `Exec=warp-terminal` PATH contract the KDE launcher relies on. The bundled
            # entry ships `Exec=warp %U`, so rewrite it to match; --replace-fail makes a
            # version bump that changes this line fail loudly instead of silently.
            extraInstallCommands = ''
              install -Dm444 ${warpAppimageContents}/usr/share/applications/dev.warp.Warp.desktop \
                -t $out/share/applications
              cp -r ${warpAppimageContents}/usr/share/icons $out/share/icons
              substituteInPlace $out/share/applications/dev.warp.Warp.desktop \
                --replace-fail 'Exec=warp ' 'Exec=warp-terminal '
            '';
          };
        in
        {
          imports = [
            ../../modules/home # core bundle (common + git + shell + rust + bun)
            ../../modules/home/linux.nix # shared Linux layer (no Windows/WSL bits)
            ../../modules/home/desktop.nix # GUI dotfiles (vscode + zed + warp + jetbrains)
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

          # Warp is installed from Nix here (see home.packages below); this module still
          # only owns its config, under the XDG paths Warp uses on Linux.
          programs.warp.settings = {
            # Native Wayland, not XWayland. Needs BOTH fixes below to hold: the
            # warp-terminal-wayland wrapper (so winit can load libwayland-client at all)
            # and the VK_DRIVER_FILES pin (so wgpu renders on the NVIDIA card, not the
            # AMD iGPU that can't present to the NVIDIA-owned surface). Without either,
            # Warp crashes on startup and rewrites this key back to true at runtime.
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
          # the nixpkgs-unstable lane because they move fast — Warp especially, since a
          # Nix-installed build can't self-update (read-only store) and nags when the
          # stable channel lags. The rest stay on stable. JetBrains defaults to IDEA
          # Ultimate (jetbrains.idea); swap the attr (e.g. jetbrains.rust-rover).
          home.packages =
            (with pkgs; [
              vscode
              jetbrains.idea
              claude-code
              discord
            ])
            ++ [
              warp-terminal-appimage # pinned upstream AppImage via appimageTools (see above)
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
