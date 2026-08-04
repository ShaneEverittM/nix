# System configuration for `exodus`, a bare-metal KDE Plasma desktop on NixOS.
# Host assembly (home-manager, shared NixOS modules) lives in ./default.nix; this file
# is the system-only layer — hardware, desktop environment, users, and services.
{
  config,
  pkgs,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Craftoria 2 Minecraft server: native systemd service + host prereqs.
    ./craftoria.nix
    # btrbk: weekly local snapshots of home + the Craftoria world subvolume.
    ./btrbk.nix
    # btrfs mount-time tuning (compress/noatime) + monthly autoScrub.
    ./btrfs.nix
    # Disk swapfile: the low-priority overflow tier layered under zram.
    ./swap.nix
    # Beszel metrics dashboard (hub + agent) exposed over Tailscale.
    ./beszel.nix
  ];

  # Personal desktop: allow the unfree apps this box runs (1Password, Warp, VS Code,
  # JetBrains, Claude Code). Broader than the shared lib/nixpkgs-config.nix predicate
  # (which the standalone home configs use), because this host installs GUI apps that
  # the CachyOS distro used to provide.
  nixpkgs.config.allowUnfree = true;

  programs._1password.enable = true;
  programs._1password-gui.enable = true;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "exodus";
  networking.networkmanager.enable = true;

  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # KDE Plasma 6 on Wayland, with the SDDM display manager.
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11.
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Graphics stack. enable32Bit pulls in the 32-bit GL/Vulkan libraries that Steam,
  # Proton, and 32-bit Wine need.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Dual-GPU desktop: the monitors are wired to the NVIDIA card (Turing, PCI 01:00.0),
  # and the AMD Raphael iGPU (0f:00.0) stays on amdgpu but drives no display. So NVIDIA
  # is simply the primary driver — no PRIME offload/sync, which is a laptop concern
  # (dGPU that can't reach the internal panel). videoDrivers = ["nvidia"] also
  # blacklists nouveau.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    # Required for the Wayland (KDE Plasma 6) session; also fixes most tearing.
    modesetting.enable = true;

    # Proprietary kernel module: the mature path for this Turing card (the open module
    # is best-tested on Ampere and newer).
    open = false;

    # Ship nvidia-settings.
    nvidiaSettings = true;

    # Desktop that stays plugged in — no need for the suspend/resume power management
    # path (which is more prone to resume glitches). Enable later if needed.
    powerManagement.enable = false;

    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Sound with PipeWire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # zsh is the shared interactive shell (see modules/home/shell.nix). Enable it
  # system-wide and make it shane's login shell declaratively — on CachyOS this took a
  # manual `chsh` because the distro owned /etc/passwd; NixOS owns it here.
  programs.zsh.enable = true;

  # AppImage runtime. AppImages assume an FHS layout NixOS doesn't provide, so they
  # can't just be chmod+x'd and run. This module ships an FHS sandbox for them, and
  # `binfmt = true` registers a kernel handler so any `*.AppImage` executes directly
  # (no `appimage-run` wrapper). Used by Cider — a paywalled build that can't be
  # fetched reproducibly into the store, so it lives as a local file in
  # ~/Applications with only its launcher entry declared in home (see default.nix).
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  # Primary user account. Set a password with `passwd` after the first switch.
  users.users."shane" = {
    isNormalUser = true;
    description = "Shane Murphy";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      kdePackages.kate
    ];
    # SSH in with the 1Password-held key (same key as the WSL host and commit signing).
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwRBMnr95gqzkvJHmNDCprKK2QcV2vNQVS6mAsGzcz3"
    ];
  };

  # SSH access over the LAN (behind the home router this is reachable only from the
  # local network unless port 22 is forwarded). Key-only, hardened like the WSL host.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "shane" ];
      MaxAuthTries = 3;
      PerSourcePenalties = "crash:3600s authfail:3600s max:86400s";
      # The tailnet is trusted (device-authenticated WireGuard), so exempt it from
      # brute-force penalties: a flaky client or a locked 1Password agent retrying
      # over Tailscale must never be able to lock me out of my own remote access.
      # 100.64.0.0/10 is Tailscale's CGNAT range. LAN/WAN keeps the hardening.
      PerSourcePenaltyExemptList = "100.64.0.0/10";
    };
  };

  # mDNS: advertise/resolve `*.local` on the LAN so this box answers to
  # `exodus.local` without a static IP. nssmdns4 wires mDNS into nsswitch so it
  # resolves other `.local` hosts too; openFirewall opens UDP 5353.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # Tailscale: stable MagicDNS name (`exodus`) + reachability from any tailnet
  # device, LAN or remote, over WireGuard. Enabling installs tailscaled + the CLI;
  # join the tailnet once with an interactive `tailscale up` (no key in this public
  # repo). SSH already works over the tailnet since port 22 is open on all
  # interfaces; scope it to the tailnet later if you want to drop LAN exposure.
  services.tailscale.enable = true;

  # Install firefox.
  programs.firefox.enable = true;

  # System profile packages (dev apps live in home.packages; see ./default.nix).
  environment.systemPackages = with pkgs; [
    vim
  ];

  # Provide a real dynamic linker at the FHS path so prebuilt/foreign binaries can run.
  programs.nix-ld.enable = true;

  # Memory-pressure resilience. 14 GiB RAM running a JVM Minecraft server (./craftoria.nix)
  # alongside the desktop. Originally this box had zero swap, so a memory spike couldn't
  # evict anonymous pages: the kernel thrashed /nix/store code pages and livelocked instead
  # of OOM-killing — which is exactly how it hard-froze once (progressive kwin/pipewire/
  # libinput stalls → 31 s freeze → power cycle).
  #
  # Two swap tiers now (see ./swap.nix for the priority hierarchy). zram: compressed in-RAM
  # swap (prio 5) so anon pages become reclaimable and the kernel/oomd can act cleanly — the
  # first-wave headroom. A low-priority disk swapfile (prio -10) sits *under* it as genuine
  # overflow capacity. earlyoom: userspace backstop that SIGTERMs the biggest hog while
  # there's still headroom, since the in-kernel OOM killer fires too late under this thrash
  # pattern.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100; # max device size; compression means real RAM used is well under this
  };

  services.earlyoom = {
    enable = true;
    # Act before the machine livelocks: kill when free RAM *and* free swap (zram) both fall
    # below these. Low RAM threshold leans on zram absorbing the first wave; the swap
    # threshold catches zram itself filling up.
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
  };

  # Crash-handling blast radius. A KDE app dying with no session to draw into -- e.g.
  # 1Password trapping on the SIGTERM systemd sends it at logout -- hands its coredump
  # to DrKonqi, whose systemd-coredump auto-launcher then recursively crashes on its
  # own missing display: the launcher aborts, dumps core, is re-launched by the socket,
  # aborts again... For hours (once observed: ~2 crashes/s for 5h, ~40 GB of coredumps,
  # a pegged core, ending in a forced power cycle from a blank-on-monitor-replug greeter).
  #
  # We don't file KDE bug reports from this box, and `coredumpctl {list,info,gdb}` still
  # gives backtraces on demand, so mask DrKonqi's coredump auto-launcher (kills the loop
  # at its mechanism) and its Sentry telemetry uploader. systemd-coredump itself stays
  # enabled -- just bounded so no future crash-storm can fill the disk. The 1Password
  # side of the trigger is handled by owning its user service (see ./default.nix).
  systemd.user.units."drkonqi-coredump-launcher.socket".enable = false;
  systemd.user.units."drkonqi-coredump-launcher@.service".enable = false;
  systemd.user.units."drkonqi-sentry-postman.service".enable = false;
  systemd.user.units."drkonqi-sentry-postman.timer".enable = false;
  systemd.user.units."drkonqi-sentry-postman.path".enable = false;

  systemd.coredump.settings.Coredump = {
    MaxUse = "2G";
    KeepFree = "5G";
    ProcessSizeMax = "2G";
  };

  # This value determines the NixOS release from which the default settings for stateful
  # data (file locations, database versions) were taken. Leave it at the release of the
  # first install; per-host, so it lives here rather than in modules/nixos/common.nix.
  system.stateVersion = "26.05";
}
