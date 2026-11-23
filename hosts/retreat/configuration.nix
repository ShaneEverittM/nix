# System configuration for `retreat`, a bare-metal headless NixOS box (Minisforum MS-A2;
# the install was migrated on its NVMe from the retired `exodus`). It used to be a KDE
# Plasma desktop, latterly reached through an on-demand Sunshine session; the whole
# graphical stack (SDDM, Plasma, PipeWire, Sunshine, the GUI apps) has since been
# dropped -- see git history. The ways in are SSH (LAN or tailnet) and the text console.
# Host assembly (home-manager, shared NixOS modules) lives in ./default.nix; this file
# is the system-only layer — hardware, networking, and services.
_: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Minecraft servers (ATM10, Craftoria 2): native systemd services + host prereqs.
    ./minecraft
    # btrbk: weekly local snapshots of home + the Minecraft world subvolumes.
    ./btrbk.nix
    # Disk swapfile: the low-priority overflow tier layered under zram.
    ./swap.nix
    # Declarative `tailscale serve` proxies (the option beszel + sure expose themselves with).
    ./tailscale-serve.nix
    # Beszel metrics dashboard (hub + agent) exposed over Tailscale.
    ./beszel.nix
    # Sure personal-finance app (upstream containers) exposed over Tailscale.
    ./sure.nix
    # Enshrouded dedicated server (community Proton container), UDP 15637.
    ./enshrouded.nix
  ];

  # 1Password CLI only (`op`). The GUI app -- and with it this host's own SSH agent and
  # op-ssh-sign -- went with the desktop; keys reach this box through the agent
  # forwarded over SSH instead (see ./default.nix).
  programs._1password.enable = true;

  networking.hostName = "retreat";
  networking.networkmanager.enable = true;

  # modules/nixos/user.nix owns the shane account. NetworkManager is this host's network
  # stack (rebirth uses wpa_supplicant), so the group that lets the account drive
  # `nmcli` lives here rather than in the shared user.
  users.users."shane".extraGroups = [ "networkmanager" ];

  # Memory-pressure resilience, tuned on this install's previous hardware (`exodus`,
  # 14 GiB) and carried over unchanged to this 32 GB box -- the headroom is far larger
  # now, so the thresholds below are conservative rather than load-bearing; retune if
  # they ever misfire. The history: a JVM Minecraft server (./minecraft) alongside the
  # then-desktop session with zero swap meant a memory spike couldn't evict anonymous pages: the
  # kernel thrashed /nix/store code pages and livelocked instead of OOM-killing -- which
  # is exactly how exodus hard-froze once (progressive kwin/pipewire/libinput stalls →
  # 31 s freeze → power cycle).
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

  # Bound systemd-coredump so no crash-storm can fill the disk. Sized after a DrKonqi
  # relaunch loop on the old desktop wrote ~40 GB of coredumps in five hours; DrKonqi is
  # gone with Plasma, but any crash-looping service could do the same.
  # `coredumpctl {list,info,gdb}` still gives backtraces on demand.
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
