# The modpacks exodus serves. Everything mechanical -- units, console FIFO, RCON wrapper,
# readiness probe, sandboxing, world subvolume, btrbk quiescing -- lives in ./service.nix;
# this file is only which packs exist and what is different about each.
#
# ONE AT A TIME. exodus has 14 GiB and a KDE session on top; two modded heaps do not fit,
# and the failure mode is not a clean OOM kill but the thrash-to-livelock this host has
# already hit once (see the memory notes in ../configuration.nix). So exactly one pack
# carries autoStart = true and the other is started by hand:
#     systemctl stop atm10 && systemctl start craftoria
#
# Both packs share 25565/25575, and that is the enforcement. Players keep one address
# whichever pack is up, and -- more usefully -- starting the second server without stopping
# the first now FAILS AT THE BIND, loudly and in seconds ("Failed to bind to port"), where
# distinct ports would have let it succeed and taken the desktop down with it. The cost is
# that "something answered on RCON" no longer identifies a pack, which is why
# `<name>-console` checks its own unit state before dialing (see ../minecraft/service.nix).
#
# Worlds are separate subvolumes regardless, so there is nothing to untangle if the RAM
# upgrade later makes concurrent packs worth it -- that is a port change plus autoStart,
# not a migration.
{ pkgs, ... }:

let
  dirs = import ./paths.nix;
in
{
  imports = [ ./service.nix ];

  publicMinecraft.servers = {
    # All the Mods 10: Minecraft 1.21.1 on NeoForge 21.1.x, Java 21. The current
    # daily-driver pack, so it owns the boot.
    #
    # ATM10 is where the THP-vs-G1 hazard in ./service.nix was first diagnosed (a G1
    # SIGSEGV in G1RegionMarkStatsCache on Java 21) -- the tmpfiles rule that forces
    # madvise is, historically, this pack's bug fix.
    atm10 = {
      description = "Minecraft server (All the Mods 10, NeoForge 1.21.1)";
      serverDir = dirs.atm10;
      jre = pkgs.jdk21_headless;
      # Same ports as craftoria, on purpose -- see the header. The pack's generated
      # server.properties must be edited to agree with these (a fresh ATM10 install ships
      # enable-rcon=false and no rcon password); the preflight fails the start until it does.
      port = 25565;
      rconPort = 25575;
      autoStart = true;
    };

    # Craftoria 2: NeoForge 26.1.2.76, Java 25. Demoted to manual start, not retired --
    # the world is live and worth keeping, which is why it stays in the btrbk timeline
    # regardless of whether it is running (the freeze hook no-ops on a stopped server, and
    # a stopped server has already flushed on SIGTERM).
    craftoria = {
      description = "Minecraft server (Craftoria 2, NeoForge 26.1.2.76)";
      serverDir = dirs.craftoria;
      jre = pkgs.jdk25_headless;
      # Unchanged 25565/25575 -- its server.properties already says so, and it is
      # out-of-store state that would have to be edited in lockstep with any change here.
      port = 25565;
      rconPort = 25575;
      autoStart = false;
    };
  };
}
