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
    # Minecraft servers (ATM10, Craftoria 2): native systemd services + host prereqs.
    ./minecraft
    # btrbk: weekly local snapshots of home + the Minecraft world subvolumes.
    ./btrbk.nix
    # Disk swapfile: the low-priority overflow tier layered under zram.
    ./swap.nix
    # Beszel metrics dashboard (hub + agent) exposed over Tailscale.
    ./beszel.nix
  ];

  programs._1password.enable = true;
  programs._1password-gui.enable = true;

  networking.hostName = "exodus";
  networking.networkmanager.enable = true;

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

  # Desktop-only extras on the shared shane account (modules/nixos/user.nix owns the
  # account itself): kate, plus the networkmanager group — NM is this desktop's network
  # stack (rebirth uses wpa_supplicant), so the group membership lives here rather than
  # in the shared user.
  users.users."shane" = {
    extraGroups = [ "networkmanager" ];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  # Advertise as a workstation on mDNS, on top of the shared avahi publish config.
  services.avahi.publish.workstation = true;

  # Install firefox.
  programs.firefox.enable = true;

  # Memory-pressure resilience. 14 GiB RAM running a JVM Minecraft server (./minecraft)
  # alongside the desktop — one pack at a time, for exactly this reason. Originally this box had zero swap, so a memory spike couldn't
  # evict anonymous pages: the kernel thrashed /nix/store code pages and livelocked instead
  # of OOM-killing — which is exactly how it hard-froze once (progressive kwin/pipewire/
  # libinput stalls → 31 s freeze → power cycle).
  #
  # Two swap tiers now (see ./swap.nix for the priority hierarchy). zram: compressed in-RAM
  # swap (prio 100) so anon pages become reclaimable and the kernel/oomd can act cleanly —
  # the first-wave headroom. A lower-priority disk swapfile (prio 10) sits *under* it as
  # genuine overflow capacity. earlyoom: userspace backstop that SIGTERMs the biggest hog
  # while there's still headroom, since the in-kernel OOM killer fires too late under this
  # thrash pattern.
  # (zramSwap.enable + earlyoom.enable come from the shared memory.nix baseline;
  # this host states the tuning.)
  zramSwap = {
    algorithm = "zstd";
    memoryPercent = 100; # max device size; compression means real RAM used is well under this
    # Explicit rather than left at the module default (5), so both tiers of the hierarchy in
    # ./swap.nix are stated in-tree. Swap priorities must be 0..32767 — see ./swap.nix.
    priority = 100;
  };

  services.earlyoom = {
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
  # first install; per-host, so it lives here rather than in the shared modules/nixos base.
  system.stateVersion = "26.05";
}
