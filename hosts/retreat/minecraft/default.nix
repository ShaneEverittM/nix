# The modpacks retreat serves. Everything mechanical lives next door: ./service.nix is
# what runs inside each pack's microVM (units, readiness probe, sandboxing, snapshot
# hooks), ./host.nix is what stays outside it (storage, snapshots), and
# ../gameservers.nix is the VM, network and on/off machinery shared with other games.
# This file is only which packs exist and what is different about each.
#
# ONE AT A TIME, enforced by the shared port. Both packs declare 25565, which puts them
# on one network slot: one tap, one guest address, one forward from the host. Starting
# either stops the other, and players keep one address whichever is up:
#     gameserver enable craftoria     # stops and disables atm10, starts craftoria
# With 32 GB this is policy, not necessity. Running both at once is a port change on
# one of them (which gives it its own slot) -- the worlds are separate subvolumes and
# the guests are already independent, so there is nothing else to untangle.
#
# `memory` is the guest's RAM and must track -Xmx in the pack's user_jvm_args.txt; see
# the option in ./options.nix before changing either.
{ pkgs, ... }:

let
  dirs = import ./paths.nix;
in
{
  imports = [ ./host.nix ];

  publicMinecraft.servers = {
    # All the Mods 10: Minecraft 1.21.1 on NeoForge 21.1.x, Java 21. The current
    # daily-driver pack, so it is the one enabled by default.
    #
    # ATM10 is where the THP-vs-G1 hazard in ./service.nix was first diagnosed (a G1
    # SIGSEGV in G1RegionMarkStatsCache on Java 21) -- the tmpfiles rule that forces
    # madvise is, historically, this pack's bug fix.
    atm10 = {
      description = "Minecraft server (All the Mods 10, NeoForge 1.21.1)";
      serverDir = dirs.atm10;
      jre = pkgs.jdk21_headless;
      port = 25565;
      rconPort = 25575;
      # -Xmx8G
      memory = 11264;
      autoStart = true;
    };

    # Craftoria 2: NeoForge 26.1.2.76, Java 25. Disabled by default, not retired -- the
    # world is live and worth keeping, which is why it stays in the btrbk timeline
    # whether or not it is running (the freeze hook no-ops on a stopped guest, and a
    # stopped server has already flushed on SIGTERM).
    craftoria = {
      description = "Minecraft server (Craftoria 2, NeoForge 26.1.2.76)";
      serverDir = dirs.craftoria;
      jre = pkgs.jdk25_headless;
      port = 25565;
      rconPort = 25575;
      # -Xmx5G
      memory = 8192;
      autoStart = false;
    };
  };
}
