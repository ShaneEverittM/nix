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
    # Minecraft servers (ATM10, Craftoria 2), each in its own microVM (./gameservers.nix).
    ./minecraft
    # btrbk: twice-daily local snapshots of home + the Minecraft world subvolumes.
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
    # Plex Media Server (native), LAN + tailnet; media in /srv/media.
    ./plex.nix
  ];

  # 1Password CLI only (`op`). The GUI app -- and with it this host's own SSH agent and
  # op-ssh-sign -- went with the desktop; keys reach this box through the agent
  # forwarded over SSH instead (see ./default.nix).
  programs._1password.enable = true;

  networking.hostName = "retreat";

  # Wired uplink on systemd-networkd. NetworkManager did this while the box was a
  # desktop; headless, all it did was run DHCP on one port, and networkd is already here
  # for the game-server taps (./gameservers.nix) -- so this makes it the only stack, and
  # the network config something that changes with a rebuild rather than with `nmcli`.
  networking.useNetworkd = true;
  # No implicit per-interface DHCP: the one .network below is the whole uplink policy.
  networking.useDHCP = false;
  systemd.network.networks."20-wired" = {
    # Every physical port, by the predictable-name prefix, rather than the one in use by
    # name: on a box with no screen, moving the cable to another port (there are four,
    # two of them SFP+) must not be how it falls off the network. `en*` is deliberately
    # narrower than Type=ether, which would also catch the guest taps and podman's veths.
    matchConfig.Name = "en*";
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
    };
    # Identify to the DHCP server by MAC, as NetworkManager did (its client-id was
    # 01:<mac>). networkd's default is a DUID, which the router would treat as a new
    # client and could hand a different address -- and the router's port forwards for
    # the game servers point at this host's address.
    dhcpV4Config.ClientIdentifier = "mac";
    linkConfig.RequiredForOnline = "routable";
  };
  # "Online" is ANY one port being routable. Every port asks for routable above, since
  # it cannot be known which one has the cable; without --any the wait would then need
  # all four and time out on the unplugged ones. The guest taps opt out entirely
  # (RequiredForOnline=no in ./gameservers.nix). btrbk's push to rebirth, among others,
  # is ordered on network-online.target, so this has to mean "has an address".
  systemd.network.wait-online.anyInterface = true;

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
